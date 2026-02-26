#!/usr/bin/env bash
#
# Generate and build Docker images for Aerospike server releases.
# Copyright 2014-2025 Aerospike, Inc. Licensed under the Apache License, Version 2.0.
# See LICENSE in the project root.
#
# Dependencies: lib/fetch.sh, lib/log.sh, lib/support.sh, lib/version.sh
# Flow: parse args -> generate_dockerfiles -> [generate_bake -> build]
#

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
cd "${SCRIPT_DIR}"

source lib/fetch.sh
source lib/log.sh
source lib/support.sh
source lib/version.sh

BAKE_FILE="bake-multi.hcl"

function usage() {
    cat <<EOF
Usage: $0 -t|-p|-g [OPTIONS] [version|lineage]

Generate Dockerfiles and build Docker images for Aerospike server releases.

MODE (one required):
    -t               Test mode - build and load locally (single platform per arch)
    -p               Push mode - build and push to registry (multi-arch manifest)
    -g, --generate   Generate Dockerfiles only (no build)

OPTIONS:
    -r, --registry REG  Container registry (and repo path) for push mode.
                        Image names: <REG>/aerospike-server[-edition]:<tag>
                        Multiple: repeat -r (e.g. -r reg1 -r reg2)
                        Default: aerospike (docker.io/aerospike/...)
                        Example: -r artifact.aerospike.io/database-docker-dev-local
    -u, --url URL       Custom artifacts URL
                        Default: https://download.aerospike.com/artifacts
                        If *.tgz is not found, falls back to *.rpm (el9/el10) or *.deb (ubuntu).
                        JFrog Artifactory RPM (el9/el10 layout):
                          https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local
                        DEB (flat layout): database-deb-prod-public-local or direct edition URL.
    -e, --edition ED    Filter edition(s): community, enterprise, federal
                        Can specify multiple: -e enterprise community
                        Default: all editions
    -d, --distro DIST   Filter distro(s): ubuntu22.04, ubuntu24.04, ubi9, ubi10
                        Prefix match: -d ubuntu (all Ubuntu), -d ubi (all UBI)
                        Can specify multiple: -d ubuntu24.04 ubi9
                        Default: all distros supported by lineage
    --no-cache          Disable Docker build cache (force full rebuild)
    -h, --help          Show this help message

VERSION/LINEAGE:
    (none)                         Build all supported lineages (7.1, 7.2, 8.0, 8.1)
    8.1                            Lineage - auto-detects latest 8.1.x version
    8.1.1.0                        Specific release version
    8.1.1.0-rc2                    Release candidate
    8.1.1.0-start-16               Development build
    8.1.1.0-start-16-gea126d3      Development build with git hash

DISTRO SUPPORT BY LINEAGE (default -d; use -d ubi10 to add ubi10):
    7.1:       ubuntu22.04, ubi9
    7.2, 8.0:  ubuntu24.04, ubi9
    8.1+:      ubuntu24.04, ubi9

OUTPUT:
    releases/<lineage>/<edition>/<distro>/    Generated Dockerfiles
    bake-multi.hcl                            Docker buildx bake file

EXAMPLES:
    # Build all editions/distros for lineage 8.1 (local test)
    $0 -t 8.1

    # Build specific edition and distro
    $0 -t 8.1 -e enterprise -d ubuntu24.04

    # Build multiple editions and distros
    $0 -t 8.1 -e enterprise community -d ubuntu24.04 ubi9

    # Build and push to registry
    $0 -p 8.1 -e enterprise federal

    # Build and push to one or more registries
    $0 -p 8.1 -e enterprise -r artifact.aerospike.io/database-docker-dev-local
    $0 -p 8.1 -e enterprise -r reg1 -r reg2

    # Generate Dockerfiles only (no build)
    $0 -g 8.1

    # Build from custom/staging artifacts server
    $0 -t 8.1.1.0-start-108 -e enterprise -d ubi9 \\
       -u https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise

    # Build all supported lineages
    $0 -g
EOF
}

#------------------------------------------------------------------------------
# Generate Dockerfiles
#------------------------------------------------------------------------------
# generate_dockerfile lineage distro edition version tools_version
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

    # When no tools version: skip tgz, go straight to native .rpm/.deb (server only)
    if [ -n "${tools_version}" ]; then
        x86_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
        x86_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
        arm_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
        arm_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
    fi

    # When -u is a local dir: always try local .rpm/.deb first (tgz/sha may exist and would skip local otherwise)
    local use_local_pkg=""
    if is_local_artifacts_dir; then
        local local_base="${ARTIFACTS_DOMAIN}"
        # Resolve relative -u to script dir so ./artifacts always means repo/artifacts
        [[ "${local_base}" != /* ]] && [[ "${local_base}" != http* ]] && local_base="${SCRIPT_DIR}/${local_base}"
        [ -d "${local_base}" ] && local_base=$(cd "${local_base}" && pwd)
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

    # If no local packages (or not local dir), use tgz or remote native rpm/deb
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

    # Skip only when we have no package (no tgz sha, no native link, and no local package)
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

    mkdir -p "${target}"
    cp template/0/entrypoint.sh "${target}/"
    cp template/7/aerospike.template.conf "${target}/"
    # Install script matches OS: scripts/rpm/install.sh for UBI, scripts/deb/install.sh for Ubuntu
    cp "scripts/${pkg_type}/install.sh" "${target}/install.sh"

    # When -u is a local dir: copy package files into build context with fixed names
    local dockerfile_copy_local=""
    local copy_files=()
    if [ -n "${use_local_pkg}" ] && [ "${pkg_format}" != "tgz" ]; then
        if [ "${pkg_type}" = "rpm" ]; then
            [ -n "${x86_link}" ] && cp "${x86_link}" "${target}/server_x86_64.rpm" && copy_files+=(server_x86_64.rpm)
            [ -n "${arm_link}" ] && cp "${arm_link}" "${target}/server_aarch64.rpm" && copy_files+=(server_aarch64.rpm)
        else
            [ -n "${x86_link}" ] && cp "${x86_link}" "${target}/server_amd64.deb" && copy_files+=(server_amd64.deb)
            [ -n "${arm_link}" ] && cp "${arm_link}" "${target}/server_arm64.deb" && copy_files+=(server_arm64.deb)
        fi
        [ ${#copy_files[@]} -gt 0 ] && dockerfile_copy_local="COPY ${copy_files[*]} /tmp/"
    fi

    # Native rpm/deb: no tools ARGs (server package only)
    local dockerfile_extra_args=""
    [ -n "${use_local_pkg}" ] && dockerfile_extra_args="ARG AEROSPIKE_LOCAL_PKG=\"1\"
"
    # (tools are skipped for native format; no AEROSPIKE_TOOLS_* ARGs)

    cat >"${target}/Dockerfile" <<DOCKERFILE
#
# Aerospike Server Dockerfile
# Version: ${version} | Edition: ${edition} | Base: ${distro}
#

FROM ${base_image}

LABEL org.opencontainers.image.title="Aerospike ${edition^} Server" \\
      org.opencontainers.image.version="${version}" \\
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="${edition}"
ARG AEROSPIKE_PKG_FORMAT="${pkg_format}"
ARG AEROSPIKE_X86_64_LINK="${x86_link}"
ARG AEROSPIKE_SHA_X86_64="${x86_sha}"
ARG AEROSPIKE_AARCH64_LINK="${arm_link}"
ARG AEROSPIKE_SHA_AARCH64="${arm_sha}"
${dockerfile_extra_args}

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh
${dockerfile_copy_local}

RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
DOCKERFILE
}

function generate_dockerfiles() {
    local version_or_lineage=$1

    log_info "=== Generating Dockerfiles ==="
    log_info "Fetching versions from ${ARTIFACTS_DOMAIN}..."
    [ ${#EDITION_FILTERS[@]} -gt 0 ] && log_info "  Editions: ${EDITION_FILTERS[*]}"
    [ ${#DISTRO_FILTERS[@]} -gt 0 ] && log_info "  Distros: ${DISTRO_FILTERS[*]}"
    echo ""

    declare -A VERSION_MAP TOOLS_MAP
    declare -ag LINEAGES_TO_BUILD=()

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
    rm -rf releases/

    for lineage in "${LINEAGES_TO_BUILD[@]}"; do
        local version="${VERSION_MAP[${lineage}]:-}"
        local tools_version="${TOOLS_MAP[${lineage}]:-}"
        [ -z "${version}" ] && continue

        local distros_lineage
        distros_lineage=$(support_distros_matching "${lineage}" "${DISTRO_FILTERS[*]:-}")
        log_info "Processing ${lineage} (${version})"

        for edition in $(support_editions); do
            if [ ${#EDITION_FILTERS[@]} -gt 0 ]; then
                local match=false
                for ef in "${EDITION_FILTERS[@]}"; do
                    [ "${ef}" = "${edition}" ] && { match=true; break; }
                done
                [ "${match}" = false ] && continue
            fi

            for distro in ${distros_lineage}; do
                generate_dockerfile "${lineage}" "${distro}" "${edition}" "${version}" "${tools_version}" || true
            done
        done
    done

    # Export for bake generation
    declare -gA G_VERSION_MAP
    for key in "${!VERSION_MAP[@]}"; do
        G_VERSION_MAP["${key}"]="${VERSION_MAP[${key}]}"
    done
}

#------------------------------------------------------------------------------
# Generate bake file and build
#------------------------------------------------------------------------------
function generate_bake() {
    local test_targets="" push_targets=""
    local test_group="" push_group=""
    local build_ts
    build_ts=$(date -u +%Y%m%d%H%M%S 2>/dev/null || date +%Y%m%d%H%M%S)

    for lineage in "${LINEAGES_TO_BUILD[@]}"; do
        local version="${G_VERSION_MAP[${lineage}]}"
        local distros_building
        distros_building=$(support_distros_matching "${lineage}" "${DISTRO_FILTERS[*]:-}")
        local omit_distro_in_tag=0
        local num_distros
        num_distros=$(echo "${distros_building}" | wc -w)
        # Single distro -> tag without distro suffix (e.g. 7.1.0.21 instead of 7.1.0.21-ubuntu22.04)
        [ "${num_distros}" -eq 1 ] && omit_distro_in_tag=1

        for edition in $(support_editions); do
            if [ ${#EDITION_FILTERS[@]} -gt 0 ]; then
                local match=false
                for ef in "${EDITION_FILTERS[@]}"; do
                    [ "${ef}" = "${edition}" ] && { match=true; break; }
                done
                [ "${match}" = false ] && continue
            fi

            for distro in ${distros_building}; do
                local ctx="./releases/${lineage}/${edition}/${distro}"
                [ ! -d "${ctx}" ] && continue

                local tag_base platforms
                tag_base="${lineage//./-}_${edition}_${distro//./-}"
                platforms=$(support_platforms "${edition}")
                local image_name="aerospike-server"
                [ "${edition}" != "community" ] && image_name+="-${edition}"
                local test_product="${REGISTRY_PREFIXES[0]}/${image_name}"

                for plat in ${platforms}; do
                    local arch=${plat#*/}
                    local test_tag
                    [ "${omit_distro_in_tag}" -eq 1 ] && test_tag="${test_product}:${version}-${arch}" || test_tag="${test_product}:${version}-${distro}-${arch}"
                    test_group+="\"${tag_base}_${arch}\", "
                    test_targets+="target \"${tag_base}_${arch}\" {
    tags=[\"${test_tag}\"]
    platforms=[\"${plat}\"]
    context=\"${ctx}\"
}
"
                done

                local push_tags=""
                for reg in "${REGISTRY_PREFIXES[@]}"; do
                    local product="${reg}/${image_name}"
                    [ -n "${push_tags}" ] && push_tags+=", "
                    if [ "${omit_distro_in_tag}" -eq 1 ]; then
                        push_tags+="\"${product}:${lineage}\", \"${product}:${version}\", \"${product}:${version}-${build_ts}\""
                    else
                        push_tags+="\"${product}:${lineage}-${distro}\", \"${product}:${version}-${distro}\", \"${product}:${version}-${distro}-${build_ts}\""
                    fi
                done
                push_group+="\"${tag_base}\", "
                push_targets+="target \"${tag_base}\" {
    tags=[${push_tags}]
    platforms=[\"${platforms// /\", \"}\"]
    context=\"${ctx}\"
}
"
            done
        done
    done

    cat >"${BAKE_FILE}" <<EOF
# Auto-generated bake file
group "test" { targets=[${test_group%,*}] }
group "push" { targets=[${push_group%,*}] }

${test_targets}
${push_targets}
EOF
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
function main() {
    local mode="" custom_url="" version_or_lineage=""
    local generate_only=false
    local bake_opts=""
    declare -ga REGISTRY_PREFIXES=()

    # Arrays for multiple values
    declare -ga EDITION_FILTERS=()
    declare -ga DISTRO_FILTERS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -t)
            mode="test"
            shift
            ;;
        -p)
            mode="push"
            shift
            ;;
        -r | --registry)
            REGISTRY_PREFIXES+=("$2")
            shift 2
            ;;
        -g | --generate)
            generate_only=true
            shift
            ;;
        -u | --url)
            custom_url="$2"
            shift 2
            ;;
        -e | --edition)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                EDITION_FILTERS+=("$1")
                shift
            done
            ;;
        -d | --distro)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                DISTRO_FILTERS+=("$1")
                shift
            done
            ;;
        --no-cache)
            bake_opts="--no-cache"
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            log_warn "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            version_or_lineage="$1"
            shift
            ;;
        esac
    done

    if [ "${generate_only}" = false ] && [ -z "${mode}" ]; then
        log_warn "Mode (-t, -p, or -g) required"
        usage
        exit 1
    fi

    [ ${#REGISTRY_PREFIXES[@]} -eq 0 ] && REGISTRY_PREFIXES=("aerospike")
    [ -n "${custom_url}" ] && export ARTIFACTS_DOMAIN="${custom_url}"

    # Step 1: Generate Dockerfiles
    generate_dockerfiles "${version_or_lineage}"

    echo ""
    log_info "Dockerfiles generated in releases/"

    # Step 2: Build (unless generate-only)
    if [ "${generate_only}" = true ]; then
        exit 0
    fi

    echo ""
    log_info "=== Building Images ==="

    generate_bake

    case "${mode}" in
    test)
        log_info "Building for local testing..."
        docker buildx bake -f "${BAKE_FILE}" test --progress plain --load ${bake_opts}
        ;;
    push)
        log_info "Building and pushing to registry/registries (${REGISTRY_PREFIXES[*]})..."
        docker buildx bake -f "${BAKE_FILE}" push --progress plain --push ${bake_opts}
        ;;
    esac

    echo ""
    log_info "Done!"
}

main "$@"
