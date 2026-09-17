#!/usr/bin/env bash
# Dockerfile generation: emit header + base-deps RUN block + inlined install RUN block + footer.
# Install logic lives in scripts/deb/install-native.sh and scripts/rpm/install-native.sh and is
# converted to a RUN \ continuation block by _sh_to_dockerfile_run (lib/sh_to_dockerfile_run.sh).
# Package URL/SHA placeholders in the install scripts are substituted with actual
# values fetched from the artifact server at generation time (no ARG indirection).
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/log.sh, lib/support.sh, lib/fetch.sh, lib/sh_to_dockerfile_run.sh
# Fragments:    lib/dockerfile_fragment_footer.docker

set -Eeuo pipefail

# generate_dockerfile lineage distro edition version
#
# Emits a Dockerfile with two RUN blocks:
#   1. Base runtime deps (apt-get/microdnf; ca-certificates, procps).
#   2. All install logic inlined as a RUN \ block with hardcoded package URLs
#      and SHAs (substituted from placeholders in scripts/{deb,rpm}/install-native.sh).
# No COPY of the install script: DOI's bashbrew build context only includes files
# committed in the upstream directory; the install scripts are not among them.
function generate_dockerfile() {
    local lineage=$1 distro=$2 edition=$3 version=$4
    local target="releases/${lineage}/${edition}/${distro}"

    log_info "  Generating ${edition}/${distro}"

    local artifact_distro pkg_type base_image
    artifact_distro=$(support_distro_to_artifact_name "${distro}")
    pkg_type=$(support_distro_to_pkg_type "${distro}")
    base_image=$(support_distro_to_base "${distro}")

    # Derive single_arch when exactly one arch is filtered
    local single_arch=""
    if [ ${#ARCH_FILTERS[@]} -eq 1 ]; then
        single_arch="${ARCH_FILTERS[0]}"
        [ "${single_arch}" = "x86_64" ] && single_arch="amd64"
        [ "${single_arch}" = "aarch64" ] && single_arch="arm64"
    fi

    # --- Resolve package links and SHAs ---
    # resolve_packages is the one implementation, shared with the in-place
    # update path: native .deb/.rpm for the server plus the latest published
    # asadm, the unused arch cleared for a single-arch build, and any arch
    # whose remote package has no usable checksum dropped. It sets the variables
    # below in this scope.
    # shellcheck disable=SC2034  # set by resolve_packages, read by _build_subst_args and _stage_local_packages via dynamic scoping
    local x86_link x86_sha arm_link arm_sha
    # shellcheck disable=SC2034  # same
    local asadm_x86_link asadm_x86_sha asadm_arm_link asadm_arm_sha
    # shellcheck disable=SC2034  # same; read by target_is_buildable
    local server_unreadable asadm_unreadable
    resolve_packages "${artifact_distro}" "${edition}" "${version}" "${single_arch}" "${pkg_type}"

    # Whether this target can be built, and why not -- one decision shared with
    # the in-place update path, which used to hold a verbatim copy of it.
    if ! target_is_buildable "${edition}" "${distro}" "${single_arch}"; then
        return 1
    fi

    # Reported per arch: a concatenation test would log "Including asadm" when
    # only one arch resolved, while the other image silently shipped without it.
    if [ "${ASADM_DISABLED}" != true ]; then
        local _asadm_src
        _asadm_src=$(asadm_source_for_pkg_type "${pkg_type}")
        if [ -n "${x86_link}" ]; then
            if [ -n "${asadm_x86_link}" ]; then
                log_info "    Including asadm (amd64): $(basename "${asadm_x86_link}")"
            else
                log_warn "    No amd64 asadm at ${_asadm_src} - the amd64 image will have none"
            fi
        fi
        if [ -n "${arm_link}" ]; then
            if [ -n "${asadm_arm_link}" ]; then
                log_info "    Including asadm (arm64): $(basename "${asadm_arm_link}")"
            else
                log_warn "    No arm64 asadm at ${_asadm_src} - the arm64 image will have none"
            fi
        fi
    fi

    # --- Prepare target directory ---
    # Nothing committed is deleted here. An `rm -rf "${target}"` also removes
    # entrypoint.sh and aerospike.template.conf, and this function runs as an
    # `if` condition with errexit suspended, so a failed cp below would neither
    # abort nor change the return status -- the loss would surface only at
    # docker build time. The cp's overwrite idempotently, and stale packages are
    # purged by _stage_local_packages, which both paths share.
    mkdir -p "${target}"
    cp template/0/entrypoint.sh "${target}/"
    chmod +x "${target}/entrypoint.sh"
    cp template/7/aerospike.template.conf "${target}/"

    # --- Resolve install script and stage local packages ---
    # Staging shared with the in-place update path.
    local install_script="${SCRIPT_DIR}/scripts/${pkg_type}/install-native.sh"
    _stage_local_packages "${target}" "${pkg_type}"

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
    # Shared with the in-place update path, so the two cannot disagree about
    # which placeholders exist.
    local -a SUBST_ARGS=()
    _build_subst_args "${pkg_type}"

    # --- Emit Dockerfile ---
    # Written outside releases/, where none of the tree's globbers can see it.
    local _df
    _df=$(mktemp "${TMPDIR:-/tmp}/as-dockerfile.XXXXXX")
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

        # For local package builds, COPY the pre-staged package file into
        # /tmp/aerospike/ before the install RUN block (the install script detects
        # an empty serverUrl and skips the curl download, using the COPY'd file).
        # asadm counts here too: -A may point at a local directory while the
        # server comes from a remote URL, and the staged asadm packages still
        # need a COPY to reach the build.
        local copy_glob
        copy_glob=$(_local_pkg_copy_glob "${pkg_type}")
        if [ -n "${copy_glob}" ]; then
            echo "COPY ${copy_glob} /tmp/aerospike/"
            echo ""
        fi

        # Inline all install logic directly as a RUN \ block.
        # For DOI: package URLs/SHAs are hardcoded (no ARG indirection, no COPY of scripts).
        # For native builds: serverUrl is empty when package is pre-staged via COPY above.
        _sh_to_dockerfile_run "${install_script}" | sed "${SUBST_ARGS[@]}"
        echo ""

        cat "${SCRIPT_DIR}/lib/dockerfile_fragment_footer.docker"
    } | sed 's/[[:space:]]*$//' | cat -s >"${_df}"

    # Ensure file ends with newline
    if [ -n "$(tail -c1 "${_df}" 2>/dev/null)" ]; then
        echo >>"${_df}"
    fi

    # The caller invokes this as an `if` condition, which suspends errexit for
    # the whole body: a mid-function failure (a broken template, a failed
    # sed/awk, a full disk) would neither abort nor change the return status.
    # Validate before the file reaches releases/, so a failed generation leaves
    # the committed Dockerfile untouched instead of replacing it with one this
    # code has just declared unusable.
    #
    # The sentinel is owned by lib/sh_to_dockerfile_run.sh; matching a hand-typed
    # copy would break every generation the first time that module reformatted
    # its output.
    local _marker
    for _marker in '^FROM ' "^$(_ere_quote "${DOCKERFILE_RUN_SENTINEL}")\$" '^ENTRYPOINT ' '^CMD '; do
        if ! grep -qE "${_marker}" "${_df}" 2>/dev/null; then
            log_warn "    Generation produced an incomplete Dockerfile (missing ${_marker})"
            rm -f "${_df}"
            return 1
        fi
    done

    # mv carries the mktemp file's 0600 across, and git tracks only the exec
    # bit, so the drop would never surface in a diff.
    chmod 644 "${_df}"

    # One rename(2): the committed Dockerfile is never absent or half-written.
    mv "${_df}" "${target}/Dockerfile"
}
