#!/usr/bin/env bash
#
# Generate and build Docker images for Aerospike server releases
#

set -Eeuo pipefail

source lib/fetch.sh
source lib/log.sh
source lib/support.sh
source lib/version.sh

BAKE_FILE="bake-multi.hcl"

function usage() {
    cat << EOF
Usage: $0 -t|-p|-g [OPTIONS] [version|lineage]

Generate Dockerfiles and build Docker images for Aerospike server releases.

MODE (one required):
    -t               Test mode - build and load locally (single platform per arch)
    -p               Push mode - build and push to registry (multi-arch manifest)
    -g, --generate   Generate Dockerfiles only (no build)

OPTIONS:
    -u, --url URL       Custom artifacts URL
                        Default: https://download.aerospike.com/artifacts
                        Can also use direct edition URL (auto-detected):
                          https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise
    -e, --edition ED    Filter edition(s): community, enterprise, federal
                        Can specify multiple: -e enterprise community
                        Default: all editions
    -d, --distro DIST   Filter distro(s): ubuntu22.04, ubuntu24.04, ubi9, ubi10
                        Can specify multiple: -d ubuntu24.04 ubi9
                        Default: all distros supported by lineage
    -h, --help          Show this help message

VERSION/LINEAGE:
    (none)                         Build all supported lineages (7.1, 7.2, 8.0, 8.1)
    8.1                            Lineage - auto-detects latest 8.1.x version
    8.1.1.0                        Specific release version
    8.1.1.0-rc2                    Release candidate
    8.1.1.0-start-16               Development build
    8.1.1.0-start-16-gea126d3      Development build with git hash

DISTRO SUPPORT BY LINEAGE:
    7.1:       ubuntu22.04, ubi9
    7.2, 8.0:  ubuntu24.04, ubi9
    8.1+:      ubuntu24.04, ubi9, ubi10

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

    # Generate Dockerfiles only (no build)
    $0 -g 8.1

    # Build from custom/staging artifacts server
    $0 -t 8.1.1.0-start-108 -e enterprise -d ubi9 \\
       -u https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise

    # Build all supported lineages
    $0 -g
EOF
}

function get_lineage_from_version() {
    echo "$1" | grep -oE '^[0-9]+\.[0-9]+'
}

#------------------------------------------------------------------------------
# Generate Dockerfiles
#------------------------------------------------------------------------------
function generate_dockerfile() {
    local lineage=$1 distro=$2 edition=$3 version=$4 tools_version=$5
    local target="releases/${lineage}/${edition}/${distro}"

    log_info "  Generating ${edition}/${distro}"

    local artifact_distro=$(support_distro_to_artifact_name "${distro}")
    local pkg_type=$(support_distro_to_pkg_type "${distro}")
    local base_image=$(support_distro_to_base "${distro}")

    local x86_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
    local x86_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
    local arm_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
    local arm_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")

    if [ -z "${x86_sha}" ]; then
        log_warn "    Skipping - package not available"
        return 1
    fi

    mkdir -p "${target}"
    cp template/0/entrypoint.sh "${target}/"
    cp template/7/aerospike.template.conf "${target}/"

    cat > "${target}/Dockerfile" << DOCKERFILE
#
# Aerospike Server Dockerfile
# Version: ${version} | Edition: ${edition} | Base: ${distro}
#

FROM ${base_image}

LABEL org.opencontainers.image.title="Aerospike ${edition^} Server" \\
      org.opencontainers.image.version="${version}" \\
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="${edition}"
ARG AEROSPIKE_X86_64_LINK="${x86_link}"
ARG AEROSPIKE_SHA_X86_64="${x86_sha}"
ARG AEROSPIKE_AARCH64_LINK="${arm_link}"
ARG AEROSPIKE_SHA_AARCH64="${arm_sha}"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

RUN \\
$(cat scripts/${pkg_type}/install.sh)

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
DOCKERFILE
}

function generate_dockerfiles() {
    local version_or_lineage=$1
    shift
    local -a edition_filters=("$@")

    log_info "=== Generating Dockerfiles ==="
    log_info "Fetching versions from ${ARTIFACTS_DOMAIN}..."
    [ ${#EDITION_FILTERS[@]} -gt 0 ] && log_info "  Editions: ${EDITION_FILTERS[*]}"
    [ ${#DISTRO_FILTERS[@]} -gt 0 ] && log_info "  Distros: ${DISTRO_FILTERS[*]}"
    echo ""

    declare -A VERSION_MAP TOOLS_MAP
    declare -ag LINEAGES_TO_BUILD=()

    if [[ "${version_or_lineage}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        local version="${version_or_lineage}"
        local lineage=$(get_lineage_from_version "${version}")
        local tools_version=$(find_tools_version "${version}")
        [ -z "${tools_version}" ] && { log_warn "${version} -> tools NOT FOUND"; exit 1; }
        VERSION_MAP["${lineage}"]="${version}"
        TOOLS_MAP["${lineage}"]="${tools_version}"
        LINEAGES_TO_BUILD=("${lineage}")
        log_info "  ${version} (lineage: ${lineage}, tools: ${tools_version})"
    elif [[ "${version_or_lineage}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        local lineage="${version_or_lineage}"
        local version=$(find_latest_version_for_lineage "${lineage}")
        [ -z "${version}" ] && { log_warn "${lineage} -> NOT FOUND"; exit 1; }
        local tools_version=$(find_tools_version "${version}")
        [ -z "${tools_version}" ] && { log_warn "${lineage} -> ${version} (tools NOT FOUND)"; exit 1; }
        VERSION_MAP["${lineage}"]="${version}"
        TOOLS_MAP["${lineage}"]="${tools_version}"
        LINEAGES_TO_BUILD=("${lineage}")
        log_info "  ${lineage} -> ${version} (tools: ${tools_version})"
    else
        for lineage in $(support_releases); do
            local version=$(find_latest_version_for_lineage "${lineage}")
            [ -z "${version}" ] && { log_warn "${lineage} -> NOT FOUND"; continue; }
            local tools_version=$(find_tools_version "${version}")
            [ -z "${tools_version}" ] && { log_warn "${lineage} -> ${version} (tools NOT FOUND)"; continue; }
            VERSION_MAP["${lineage}"]="${version}"
            TOOLS_MAP["${lineage}"]="${tools_version}"
            LINEAGES_TO_BUILD+=("${lineage}")
            log_info "  ${lineage} -> ${version} (tools: ${tools_version})"
        done
    fi

    echo ""
    rm -rf releases/

    for lineage in "${LINEAGES_TO_BUILD[@]}"; do
        local version="${VERSION_MAP[${lineage}]:-}"
        local tools_version="${TOOLS_MAP[${lineage}]:-}"
        [ -z "${version}" ] && continue

        local all_distros=$(support_distros "${lineage}")
        log_info "Processing ${lineage} (${version})"

        for edition in $(support_editions); do
            # Check edition filter
            if [ ${#EDITION_FILTERS[@]} -gt 0 ]; then
                local match=false
                for ef in "${EDITION_FILTERS[@]}"; do
                    [ "${ef}" = "${edition}" ] && match=true && break
                done
                [ "${match}" = false ] && continue
            fi

            for distro in ${all_distros}; do
                # Check distro filter
                if [ ${#DISTRO_FILTERS[@]} -gt 0 ]; then
                    local match=false
                    for df in "${DISTRO_FILTERS[@]}"; do
                        [ "${df}" = "${distro}" ] && match=true && break
                    done
                    [ "${match}" = false ] && continue
                fi

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

    for lineage in "${LINEAGES_TO_BUILD[@]}"; do
        local version="${G_VERSION_MAP[${lineage}]}"
        local all_distros=$(support_distros "${lineage}")

        for edition in $(support_editions); do
            # Check edition filter
            if [ ${#EDITION_FILTERS[@]} -gt 0 ]; then
                local match=false
                for ef in "${EDITION_FILTERS[@]}"; do
                    [ "${ef}" = "${edition}" ] && match=true && break
                done
                [ "${match}" = false ] && continue
            fi

            for distro in ${all_distros}; do
                # Check distro filter
                if [ ${#DISTRO_FILTERS[@]} -gt 0 ]; then
                    local match=false
                    for df in "${DISTRO_FILTERS[@]}"; do
                        [ "${df}" = "${distro}" ] && match=true && break
                    done
                    [ "${match}" = false ] && continue
                fi

                local ctx="./releases/${lineage}/${edition}/${distro}"
                [ ! -d "${ctx}" ] && continue

                local tag_base="${lineage//./-}_${edition}_${distro//./-}"
                local platforms=$(support_platforms "${edition}")
                local product="aerospike/aerospike-server"
                [ "${edition}" != "community" ] && product+="-${edition}"

                for plat in ${platforms}; do
                    local arch=${plat#*/}
                    test_group+="\"${tag_base}_${arch}\", "
                    test_targets+="target \"${tag_base}_${arch}\" {
    tags=[\"${product}:${version}-${distro//./-}-${arch}\"]
    platforms=[\"${plat}\"]
    context=\"${ctx}\"
}
"
                done

                push_group+="\"${tag_base}\", "
                push_targets+="target \"${tag_base}\" {
    tags=[\"${product}:${version}\", \"${product}:${version}-${distro//./-}\"]
    platforms=[\"${platforms// /\", \"}\"]
    context=\"${ctx}\"
}
"
            done
        done
    done

    cat > "${BAKE_FILE}" << EOF
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

    # Arrays for multiple values
    declare -ga EDITION_FILTERS=()
    declare -ga DISTRO_FILTERS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t)            mode="test"; shift ;;
            -p)            mode="push"; shift ;;
            -g|--generate) generate_only=true; shift ;;
            -u|--url)      custom_url="$2"; shift 2 ;;
            -e|--edition)
                shift
                while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                    EDITION_FILTERS+=("$1")
                    shift
                done
                ;;
            -d|--distro)
                shift
                while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                    DISTRO_FILTERS+=("$1")
                    shift
                done
                ;;
            -h|--help)     usage; exit 0 ;;
            -*)            log_warn "Unknown option: $1"; usage; exit 1 ;;
            *)             version_or_lineage="$1"; shift ;;
        esac
    done

    if [ "${generate_only}" = false ] && [ -z "${mode}" ]; then
        log_warn "Mode (-t, -p, or -g) required"
        usage
        exit 1
    fi

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
            docker buildx bake -f "${BAKE_FILE}" test --progress plain --load
            ;;
        push)
            log_info "Building and pushing to registry..."
            docker buildx bake -f "${BAKE_FILE}" push --progress plain --push
            ;;
    esac

    echo ""
    log_info "Done!"
}

main "$@"
