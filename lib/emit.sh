#!/usr/bin/env bash
# Dockerfile generation: emit header + RUN heredoc (install.sh inlined) + footer.
# The install logic now lives in scripts/deb/install.sh and scripts/rpm/install.sh.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/log.sh, lib/support.sh, lib/fetch.sh

set -Eeuo pipefail

# generate_dockerfile lineage distro edition version tools_version
#
# Emits a compact Dockerfile that runs the install script via RUN <<heredoc (BuildKit).
# No COPY of install.sh (policy scanners). Logic is in scripts/{deb,rpm}/install.sh.
function generate_dockerfile() {
    local lineage=$1 distro=$2 edition=$3 version=$4 tools_version=$5
    local target="releases/${lineage}/${edition}/${distro}"

    log_info "  Generating ${edition}/${distro}"

    local artifact_distro pkg_type base_image
    artifact_distro=$(support_distro_to_artifact_name "${distro}")
    pkg_type=$(support_distro_to_pkg_type "${distro}")
    base_image=$(support_distro_to_base "${distro}")

    local x86_link="" x86_sha="" arm_link="" arm_sha=""
    local pkg_format="tgz"

    # Derive single_arch when exactly one arch is filtered
    local single_arch=""
    if [ ${#ARCH_FILTERS[@]} -eq 1 ]; then
        single_arch="${ARCH_FILTERS[0]}"
        [ "${single_arch}" = "x86_64" ] && single_arch="amd64"
        [ "${single_arch}" = "aarch64" ] && single_arch="arm64"
    fi

    # --- Resolve package links and SHAs ---
    if [ -n "${tools_version}" ]; then
        x86_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
        x86_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
        arm_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
        arm_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
    fi

    # Local dir packages (-u <dir>)
    local use_local_pkg=""
    if is_local_artifacts_dir; then
        local local_base="${ARTIFACTS_DOMAIN}"
        [[ "${local_base}" != /* ]] && [[ "${local_base}" != http* ]] && local_base="${SCRIPT_DIR}/${local_base}"
        [ -d "${local_base}" ] && local_base=$(
            cd "${local_base}" || exit 1
            pwd
        )
        local local_x86 local_arm
        local_x86=$(find_local_server_package "${local_base}" "${artifact_distro}" "${edition}" "${version}" "x86_64" "${pkg_type}")
        local_arm=$(find_local_server_package "${local_base}" "${artifact_distro}" "${edition}" "${version}" "aarch64" "${pkg_type}")
        if [ -n "${local_x86}" ] || [ -n "${local_arm}" ]; then
            pkg_format="${pkg_type}"
            [ -n "${local_x86}" ] && x86_link="${local_x86}"
            [ -n "${local_arm}" ] && arm_link="${local_arm}"
            use_local_pkg="1"
        fi
    fi

    # Fallback to remote native rpm/deb when tgz not available
    if [ -z "${use_local_pkg}" ] && [ -z "${x86_sha}" ]; then
        if ! is_local_artifacts_dir; then
            x86_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64" "${pkg_type}")
            x86_sha=$(fetch_sha_for_link "${x86_link}")
            if [ -n "${x86_link}" ]; then
                pkg_format="${pkg_type}"
                arm_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64" "${pkg_type}")
                arm_sha=$(fetch_sha_for_link "${arm_link}")
            fi
        fi
    fi

    # When building single-arch, clear unused arch.
    # Federal edition is x86-only, so arm_link/arm_sha will already be empty.
    if [ "${single_arch}" = "amd64" ]; then
        arm_link=""
        arm_sha=""
    fi
    if [ "${single_arch}" = "arm64" ]; then
        x86_link=""
        x86_sha=""
    fi

    # Skip when no package available
    if [ -z "${x86_sha}" ] && [ -z "${use_local_pkg}" ] && { [ "${pkg_format}" = "tgz" ] || [ -z "${x86_link}" ]; }; then
        log_warn "    Skipping - package not available (tried tgz and ${pkg_type})"
        return 1
    fi
    if [ -z "${x86_sha}" ] && [ -n "${use_local_pkg}" ] && [ -z "${x86_link}" ] && [ -z "${arm_link}" ]; then
        log_warn "    Skipping - no local package found"
        return 1
    fi

    [ "${pkg_format}" != "tgz" ] && log_info "    Using native ${pkg_format} (tgz not found)"
    [ -n "${use_local_pkg}" ] && log_info "    Using local packages from ${ARTIFACTS_DOMAIN}"

    # --- Prepare target directory ---
    mkdir -p "${target}"
    cp template/0/entrypoint.sh "${target}/"
    chmod +x "${target}/entrypoint.sh"
    cp template/7/aerospike.template.conf "${target}/"

    mkdir -p "${target}/static/tini"
    cp "${SCRIPT_DIR}/static/tini/as-tini-static-amd64" "${SCRIPT_DIR}/static/tini/as-tini-static-arm64" "${target}/static/tini/"

    # Resolve the install script path (not copied into the build context —
    # DOI does not support COPY of build-time-only scripts; logic is inlined
    # directly in the Dockerfile as a RUN \ block via sh_to_dockerfile_run.py).
    local install_script
    if [ "${pkg_type}" = "deb" ]; then
        install_script="${SCRIPT_DIR}/scripts/deb/install.sh"
    else
        install_script="${SCRIPT_DIR}/scripts/rpm/install.sh"
    fi

    # --- Handle local packages: copy into context, generate COPY line ---
    local dockerfile_copy_local=""
    local copy_files=()
    if [ -n "${use_local_pkg}" ] && [ "${pkg_format}" != "tgz" ]; then
        local need_sha=false
        [ -n "${x86_link}" ] && [ ! -f "${x86_link}.sha256" ] && need_sha=true
        [ -n "${arm_link}" ] && [ ! -f "${arm_link}.sha256" ] && need_sha=true
        if [ "${need_sha}" = true ]; then
            local local_base="${ARTIFACTS_DOMAIN}"
            [[ "${local_base}" != /* ]] && [[ "${local_base}" != http* ]] && local_base="${SCRIPT_DIR}/${local_base}"
            [ -d "${local_base}" ] && local_base=$(
                cd "${local_base}" || exit 1
                pwd
            )
            if [ -d "${local_base}" ]; then
                log_info "    Creating missing .sha256 in ${local_base} (shasum-artifacts.sh)"
                "${SCRIPT_DIR}/scripts/shasum-artifacts.sh" "${local_base}" >/dev/null 2>&1 || true
            fi
        fi
        if [ "${pkg_type}" = "rpm" ]; then
            if [ -n "${x86_link}" ]; then
                cp "${x86_link}" "${target}/server_x86_64.rpm" && copy_files+=(server_x86_64.rpm)
                [ -f "${x86_link}.sha256" ] && cp "${x86_link}.sha256" "${target}/server_x86_64.rpm.sha256" && copy_files+=(server_x86_64.rpm.sha256) && x86_sha=$(awk '{print $1}' "${x86_link}.sha256")
            fi
            if [ -n "${arm_link}" ]; then
                cp "${arm_link}" "${target}/server_aarch64.rpm" && copy_files+=(server_aarch64.rpm)
                [ -f "${arm_link}.sha256" ] && cp "${arm_link}.sha256" "${target}/server_aarch64.rpm.sha256" && copy_files+=(server_aarch64.rpm.sha256) && arm_sha=$(awk '{print $1}' "${arm_link}.sha256")
            fi
        else
            if [ -n "${x86_link}" ]; then
                cp "${x86_link}" "${target}/server_amd64.deb" && copy_files+=(server_amd64.deb)
                [ -f "${x86_link}.sha256" ] && cp "${x86_link}.sha256" "${target}/server_amd64.deb.sha256" && copy_files+=(server_amd64.deb.sha256) && x86_sha=$(awk '{print $1}' "${x86_link}.sha256")
            fi
            if [ -n "${arm_link}" ]; then
                cp "${arm_link}" "${target}/server_arm64.deb" && copy_files+=(server_arm64.deb)
                [ -f "${arm_link}.sha256" ] && cp "${arm_link}.sha256" "${target}/server_arm64.deb.sha256" && copy_files+=(server_arm64.deb.sha256) && arm_sha=$(awk '{print $1}' "${arm_link}.sha256")
            fi
        fi
        [ ${#copy_files[@]} -gt 0 ] && dockerfile_copy_local="COPY ${copy_files[*]} /tmp/"
    fi

    # --- Build Dockerfile variables ---
    # ARG AEROSPIKE_COMPAT_LIBS is only needed for 7.2 on ubuntu24.04 (legacy libs);
    # omit it for all other versions to match the DOI-accepted reference structure.
    local compat_libs_arg=""
    if [[ "${distro}" == ubuntu24.04 ]] && [[ "${lineage}" == "7.2" ]]; then
        compat_libs_arg='ARG AEROSPIKE_COMPAT_LIBS="1"'
    fi

    local dockerfile_extra_args=""
    [ -n "${use_local_pkg}" ] && dockerfile_extra_args="ARG AEROSPIKE_LOCAL_PKG=\"1\""
    local dockerfile_x86_args=""
    if [ "${single_arch}" != "arm64" ]; then
        dockerfile_x86_args="ARG AEROSPIKE_X86_64_LINK=\"${x86_link}\"
ARG AEROSPIKE_SHA_X86_64=\"${x86_sha}\""
    fi
    local dockerfile_aarch64_args=""
    if [ "${single_arch}" != "amd64" ]; then
        dockerfile_aarch64_args="ARG AEROSPIKE_AARCH64_LINK=\"${arm_link}\"
ARG AEROSPIKE_SHA_AARCH64=\"${arm_sha}\""
    fi
    local base_name_label="${base_image}"
    [[ "${base_image}" == ubuntu:* ]] && base_name_label="docker.io/library/${base_image}"

    # --- Emit Dockerfile ---
    {
        cat <<HEADER

#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM ${base_image}

LABEL org.opencontainers.image.title="Aerospike ${edition^} Server" \\
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \\
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \\
      org.opencontainers.image.base.name="${base_name_label}" \\
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \\
      org.opencontainers.image.vendor="Aerospike" \\
      org.opencontainers.image.version="${version}" \\
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="${edition}"

ENV AEROSPIKE_LINUX_BASE="${base_image}"
${dockerfile_x86_args}
${dockerfile_aarch64_args}
${compat_libs_arg}
${dockerfile_extra_args}

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

HEADER

        cat "${SCRIPT_DIR}/lib/dockerfile_fragment_tini.docker"
        echo ""

        # Optional COPY for local packages (before install script)
        if [ -n "${dockerfile_copy_local}" ]; then
            echo "${dockerfile_copy_local}"
            echo ""
        fi

        # Inline all install logic directly as a RUN \ block (DOI-accepted pattern).
        # DOI rejects BuildKit heredocs AND COPY of build-time scripts — the build
        # context only contains Dockerfile + runtime support files (no install.sh).
        python3 "${SCRIPT_DIR}/lib/sh_to_dockerfile_run.py" "${install_script}"
        echo ""

        # Footer
        cat <<FOOTER
# Add the Aerospike configuration specific to this dockerfile
COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf

# Mount the Aerospike data directory
# VOLUME ["/opt/aerospike/data"]
# Mount the Aerospike config directory
# VOLUME ["/etc/aerospike/"]

# Expose Aerospike ports
#
#   3000 – service port, for client connections
#   3001 – fabric port, for cluster communication
#   3002 – mesh port, for cluster heartbeat
#
EXPOSE 3000 3001 3002

COPY entrypoint.sh /entrypoint.sh

# Tini init set to restart ASD on SIGUSR1 and terminate ASD on SIGTERM
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Execute the run script in foreground mode
CMD ["asd"]
FOOTER
    } | sed 's/[[:space:]]*$//' | cat -s >"${target}/Dockerfile"

    # Ensure file ends with newline
    if [ -n "$(tail -c1 "${target}/Dockerfile" 2>/dev/null)" ]; then
        echo >>"${target}/Dockerfile"
    fi
}
