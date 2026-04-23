#!/usr/bin/env bash
# Dockerfile generation: emit header + base-deps RUN block + inlined install RUN block + footer.
# Install logic lives in scripts/deb/install.sh and scripts/rpm/install.sh and is
# converted to a RUN \ continuation block by _sh_to_dockerfile_run (lib/sh_to_dockerfile_run.sh).
# Package URL/SHA placeholders in the install scripts are substituted with actual
# values fetched from the artifact server at generation time (no ARG indirection).
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/log.sh, lib/support.sh, lib/fetch.sh, lib/sh_to_dockerfile_run.sh
# Fragments:    lib/dockerfile_fragment_footer.docker

set -Eeuo pipefail

# generate_dockerfile lineage distro edition version tools_version
#
# Emits a Dockerfile with two RUN blocks:
#   1. Base runtime deps (apt-get/microdnf; ca-certificates, procps).
#   2. All install logic inlined as a RUN \ block with hardcoded package URLs
#      and SHAs (substituted from placeholders in scripts/{deb,rpm}/install.sh).
# No COPY of install.sh: DOI's bashbrew build context only includes files committed
# in the upstream directory; install.sh is not among them.
function generate_dockerfile() {
    local lineage=$1 distro=$2 edition=$3 version=$4 tools_version=$5
    local target="releases/${lineage}/${edition}/${distro}"

    log_info "  Generating ${edition}/${distro}"

    local artifact_distro pkg_type base_image
    artifact_distro=$(support_distro_to_artifact_name "${distro}")
    pkg_type=$(support_distro_to_pkg_type "${distro}")
    base_image=$(support_distro_to_base "${distro}")

    local x86_link="" x86_sha="" arm_link="" arm_sha=""
    local use_native=false  # true when falling back to native .deb/.rpm (no TGZ bundle)

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

    # Fallback to native rpm/deb when tgz not available
    if [ -z "${x86_sha}" ]; then
        use_native=true
        x86_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64" "${pkg_type}")
        x86_sha=$(fetch_sha_for_link "${x86_link}")
        if [ -n "${x86_link}" ]; then
            arm_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64" "${pkg_type}")
            arm_sha=$(fetch_sha_for_link "${arm_link}")
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
    if [ -z "${x86_sha}" ] && [ -z "${x86_link}" ]; then
        log_warn "    Skipping - package not available"
        return 1
    fi

    # --- Prepare target directory ---
    mkdir -p "${target}"
    cp template/0/entrypoint.sh "${target}/"
    chmod +x "${target}/entrypoint.sh"
    cp template/7/aerospike.template.conf "${target}/"

    # --- Resolve install script ---
    # TGZ bundles use the standard install scripts (server + tools via curl).
    # Native packages (.deb/.rpm only, no tools) use the -native variants.
    # For local file paths, the package is staged in the build context via COPY;
    # for remote HTTP URLs the native scripts download the file via curl.
    local install_script
    if "${use_native}"; then
        if [ "${pkg_type}" = "deb" ]; then
            install_script="${SCRIPT_DIR}/scripts/deb/install-native.sh"
        else
            install_script="${SCRIPT_DIR}/scripts/rpm/install-native.sh"
        fi
        # Copy local package files into the build context so Dockerfile COPY works.
        # Also stage any tools package found alongside the server package so that
        # apt-get / rpm can satisfy a hard Depends/Requires on aerospike-tools.
        local _dir _tools_f
        if [[ "${x86_link}" != http* ]] && [ -n "${x86_link}" ] && [ -f "${x86_link}" ]; then
            cp "${x86_link}" "${target}/"
            _dir=$(dirname "${x86_link}")
            if [ "${pkg_type}" = "deb" ]; then
                _tools_f=$(find "${_dir}" -maxdepth 1 -type f -name "aerospike-tools-*_amd64.deb" 2>/dev/null | sort -V | tail -1)
            else
                _tools_f=$(find "${_dir}" -maxdepth 1 -type f -name "aerospike-tools-*.x86_64.rpm" 2>/dev/null | sort -V | tail -1)
            fi
            [ -n "${_tools_f}" ] && [ -f "${_tools_f}" ] && cp "${_tools_f}" "${target}/"
        fi
        if [[ "${arm_link}" != http* ]] && [ -n "${arm_link}" ] && [ -f "${arm_link}" ]; then
            cp "${arm_link}" "${target}/"
            _dir=$(dirname "${arm_link}")
            if [ "${pkg_type}" = "deb" ]; then
                _tools_f=$(find "${_dir}" -maxdepth 1 -type f -name "aerospike-tools-*_arm64.deb" 2>/dev/null | sort -V | tail -1)
            else
                _tools_f=$(find "${_dir}" -maxdepth 1 -type f -name "aerospike-tools-*.aarch64.rpm" 2>/dev/null | sort -V | tail -1)
            fi
            [ -n "${_tools_f}" ] && [ -f "${_tools_f}" ] && cp "${_tools_f}" "${target}/"
        fi
    else
        if [ "${pkg_type}" = "deb" ]; then
            install_script="${SCRIPT_DIR}/scripts/deb/install.sh"
        else
            install_script="${SCRIPT_DIR}/scripts/rpm/install.sh"
        fi
    fi

    local base_name_label="${base_image}"
    [[ "${base_image}" == ubuntu:* ]] && base_name_label="docker.io/library/${base_image}"

    # --- Base-deps RUN block (pkg-type specific) ---
    local base_deps_run=""
    if [ "${pkg_type}" = "deb" ]; then
        base_deps_run='# hadolint ignore=DL3008
RUN \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    ca-certificates \
    procps \
  ; \
  rm -rf /var/lib/apt/lists/*'
    else
        base_deps_run='# hadolint ignore=DL3041
RUN \
  microdnf install -y --setopt=install_weak_deps=0 \
    ca-certificates \
    procps-ng \
  ; \
  microdnf clean all; \
  rm -rf /var/cache/yum /var/cache/dnf'
    fi

    # --- Placeholder substitution for package URLs/SHAs ---
    # TGZ scripts use __PKG_URL_* / __PKG_SHA_* placeholders.
    # Native scripts use __SERVER_URL_* / __SERVER_SHA_* placeholders.
    # For local file builds, URL placeholders are substituted to empty strings so
    # the install script skips the curl download (package is pre-staged via COPY).
    local -a subst_args=()
    if "${use_native}"; then
        # Native .deb/.rpm: empty URL = use COPY'd file; HTTP URL = curl download.
        local _x86_url="" _x86_sha_val="" _arm_url="" _arm_sha_val=""
        [[ "${x86_link}" == http* ]] && _x86_url="${x86_link}" && _x86_sha_val="${x86_sha}"
        [[ "${arm_link}" == http* ]] && _arm_url="${arm_link}" && _arm_sha_val="${arm_sha}"
        if [ "${pkg_type}" = "deb" ]; then
            subst_args=(
                -e "s|__SERVER_URL_AMD64__|${_x86_url}|g"
                -e "s|__SERVER_SHA_AMD64__|${_x86_sha_val}|g"
                -e "s|__SERVER_URL_ARM64__|${_arm_url}|g"
                -e "s|__SERVER_SHA_ARM64__|${_arm_sha_val}|g"
            )
        else
            subst_args=(
                -e "s|__SERVER_URL_X86_64__|${_x86_url}|g"
                -e "s|__SERVER_SHA_X86_64__|${_x86_sha_val}|g"
                -e "s|__SERVER_URL_AARCH64__|${_arm_url}|g"
                -e "s|__SERVER_SHA_AARCH64__|${_arm_sha_val}|g"
            )
        fi
    elif [ "${pkg_type}" = "deb" ]; then
        subst_args=(
            -e "s|__PKG_URL_AMD64__|${x86_link}|g"
            -e "s|__PKG_SHA_AMD64__|${x86_sha}|g"
            -e "s|__PKG_URL_ARM64__|${arm_link}|g"
            -e "s|__PKG_SHA_ARM64__|${arm_sha}|g"
        )
    else
        subst_args=(
            -e "s|__PKG_URL_X86_64__|${x86_link}|g"
            -e "s|__PKG_SHA_X86_64__|${x86_sha}|g"
            -e "s|__PKG_URL_AARCH64__|${arm_link}|g"
            -e "s|__PKG_SHA_AARCH64__|${arm_sha}|g"
        )
    fi

    # --- Emit Dockerfile ---
    {
        cat <<HEADER

#
# Aerospike Server Dockerfile
#
# https://github.com/aerospike/aerospike-server.docker
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

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

HEADER

        echo "${base_deps_run}"
        echo ""

        # For local native package builds, COPY the pre-staged package file into
        # /tmp/aerospike/ before the install RUN block (the install script detects
        # an empty serverUrl and skips the curl download, using the COPY'd file).
        if "${use_native}"; then
            local copy_glob=""
            [ "${pkg_type}" = "deb" ] && copy_glob="*.deb"
            [ "${pkg_type}" = "rpm" ] && copy_glob="*.rpm"
            local has_local=false
            [[ "${x86_link}" != http* ]] && [ -n "${x86_link}" ] && has_local=true
            [[ "${arm_link}" != http* ]] && [ -n "${arm_link}" ] && has_local=true
            if "${has_local}"; then
                echo "COPY ${copy_glob} /tmp/aerospike/"
                echo ""
            fi
        fi

        # Inline all install logic directly as a RUN \ block.
        # For DOI: package URLs/SHAs are hardcoded (no ARG indirection, no COPY of scripts).
        # For native builds: serverUrl is empty when package is pre-staged via COPY above.
        _sh_to_dockerfile_run "${install_script}" | sed "${subst_args[@]}"
        echo ""

        cat "${SCRIPT_DIR}/lib/dockerfile_fragment_footer.docker"
    } | sed 's/[[:space:]]*$//' | cat -s >"${target}/Dockerfile"

    # Ensure file ends with newline
    if [ -n "$(tail -c1 "${target}/Dockerfile" 2>/dev/null)" ]; then
        echo >>"${target}/Dockerfile"
    fi
}
