#!/usr/bin/env bash
# Orchestrate Dockerfile generation: version discovery -> per-lineage loop.
# Routes between full generation (-g / missing Dockerfile) and in-place update.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/log.sh, lib/support.sh, lib/fetch.sh, lib/sh_to_dockerfile_run.sh, lib/emit.sh, lib/update.sh

set -Eeuo pipefail

# generate_dockerfiles version_or_lineage full_generate
#   version_or_lineage: "8.1", "8.1.1.0", or "" (all lineages)
#   full_generate:      "true" to always regenerate, "false" to update in-place
function generate_dockerfiles() {
    local version_or_lineage=$1
    local full_generate=${2:-false}

    log_info "=== Generating Dockerfiles ==="
    log_info "Fetching versions from ${ARTIFACTS_DOMAIN}..."
    [ ${#EDITION_FILTERS[@]} -gt 0 ] && log_info "  Editions: ${EDITION_FILTERS[*]}"
    [ ${#DISTRO_FILTERS[@]} -gt 0 ] && log_info "  Distros: ${DISTRO_FILTERS[*]}"
    echo ""

    declare -A VERSION_MAP TOOLS_MAP
    declare -ag LINEAGES_TO_BUILD=()

    # --- Resolve version(s) ---
    if [[ "${version_or_lineage}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        local version="${version_or_lineage}"
        local lineage tools_version
        lineage=$(get_lineage_from_version "${version}")
        tools_version=$(find_tools_version "${version}")
        VERSION_MAP["${lineage}"]="${version}"
        TOOLS_MAP["${lineage}"]="${tools_version:-}"
        LINEAGES_TO_BUILD=("${lineage}")
        if [ -z "${tools_version}" ]; then
            log_warn "${version} -> tools NOT FOUND (will try native .rpm/.deb only, no tools)"
        else
            log_info "  ${version} (lineage: ${lineage}, tools: ${tools_version})"
        fi
    elif [[ "${version_or_lineage}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        local lineage="${version_or_lineage}"
        local version tools_version
        version=$(find_latest_version_for_lineage "${lineage}")
        [ -z "${version}" ] && {
            log_warn "${lineage} -> NOT FOUND"
            exit 1
        }
        tools_version=$(find_tools_version "${version}")
        VERSION_MAP["${lineage}"]="${version}"
        TOOLS_MAP["${lineage}"]="${tools_version:-}"
        LINEAGES_TO_BUILD=("${lineage}")
        if [ -z "${tools_version}" ]; then
            log_warn "${lineage} -> ${version} (tools NOT FOUND; will try native .rpm/.deb only, no tools)"
        else
            log_info "  ${lineage} -> ${version} (tools: ${tools_version})"
        fi
    else
        # shellcheck disable=SC2086
        for lineage in $(support_releases); do
            local version tools_version
            version=$(find_latest_version_for_lineage "${lineage}")
            [ -z "${version}" ] && {
                log_warn "${lineage} -> NOT FOUND"
                continue
            }
            tools_version=$(find_tools_version "${version}")
            VERSION_MAP["${lineage}"]="${version}"
            TOOLS_MAP["${lineage}"]="${tools_version:-}"
            LINEAGES_TO_BUILD+=("${lineage}")
            if [ -z "${tools_version}" ]; then
                log_warn "${lineage} -> ${version} (tools NOT FOUND; will try native .rpm/.deb only)"
            else
                log_info "  ${lineage} -> ${version} (tools: ${tools_version})"
            fi
        done
    fi

    if [ ${#LINEAGES_TO_BUILD[@]} -eq 0 ]; then
        log_warn "Nothing to build (no version/lineage had packages available). Use -u for a custom server with native rpm/deb."
        exit 1
    fi

    echo ""

    # Full generate cleans only the lineages we're about to rebuild
    if [ "${full_generate}" = true ]; then
        for lineage in "${LINEAGES_TO_BUILD[@]}"; do
            [ -d "releases/${lineage}" ] && rm -rf "releases/${lineage}"
        done
    fi

    # --- Per-lineage / edition / distro loop ---
    for lineage in "${LINEAGES_TO_BUILD[@]}"; do
        local version="${VERSION_MAP[${lineage}]:-}"
        local tools_version="${TOOLS_MAP[${lineage}]:-}"
        [ -z "${version}" ] && continue

        local distros_lineage
        distros_lineage=$(support_distros_matching "${lineage}" "${DISTRO_FILTERS[*]:-}")
        log_info "Processing ${lineage} (${version})"

        # shellcheck disable=SC2086
        for edition in $(support_editions); do
            if [ ${#EDITION_FILTERS[@]} -gt 0 ]; then
                local match=false
                for ef in "${EDITION_FILTERS[@]}"; do
                    [ "${ef}" = "${edition}" ] && {
                        match=true
                        break
                    }
                done
                [ "${match}" = false ] && continue
            fi

            # shellcheck disable=SC2086
            for distro in ${distros_lineage}; do
                local target="releases/${lineage}/${edition}/${distro}"

                if [ "${full_generate}" = true ] || [ ! -f "${target}/Dockerfile" ]; then
                    # Full generate (or Dockerfile missing -- auto-fallback)
                    generate_dockerfile "${lineage}" "${distro}" "${edition}" "${version}" "${tools_version}" || true
                else
                    # In-place update
                    local artifact_distro pkg_type
                    artifact_distro=$(support_distro_to_artifact_name "${distro}")
                    pkg_type=$(support_distro_to_pkg_type "${distro}")

                    local single_arch=""
                    if [ ${#ARCH_FILTERS[@]} -eq 1 ]; then
                        single_arch="${ARCH_FILTERS[0]}"
                        [ "${single_arch}" = "x86_64" ] && single_arch="amd64"
                        [ "${single_arch}" = "aarch64" ] && single_arch="arm64"
                    fi

                    # shellcheck disable=SC2034  # set by resolve_packages, consumed by update_dockerfile
                    local x86_link x86_sha arm_link arm_sha pkg_format
                    resolve_packages "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "${single_arch}" "${pkg_type}"

                    if [ -z "${x86_sha}" ] && [ -z "${x86_link}" ]; then
                        log_warn "    Skipping ${edition}/${distro} - package not available"
                        continue
                    fi

                    [ "${pkg_format}" != "tgz" ] && log_info "    Using native ${pkg_format} (tgz not found)"

                    update_dockerfile "${target}" "${version}" "${single_arch}"
                fi
            done
        done
    done

    # shellcheck disable=SC2034  # consumed by generate_bake in caller scope
    declare -gA G_VERSION_MAP
    for key in "${!VERSION_MAP[@]}"; do
        # shellcheck disable=SC2034  # consumed by generate_bake in caller scope
        G_VERSION_MAP["${key}"]="${VERSION_MAP[${key}]}"
    done
}
