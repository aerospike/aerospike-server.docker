#!/usr/bin/env bash
#
# Functional tests for Aerospike server Docker images.
# Copyright 2014-2025 Aerospike, Inc. Licensed under the Apache License, Version 2.0.
# See LICENSE in the project root.
#
# Dependencies: lib/log.sh, lib/support.sh, lib/version.sh
# Tag format must match docker-build.sh (single-distro: version-arch; multi: version-distro-arch).
#

set -Eeuo pipefail

source lib/log.sh
source lib/support.sh
source lib/version.sh

function usage() {
    cat <<EOF
Usage: $0 [version|lineage] [OPTIONS]
       $0 -i IMAGE [OPTIONS]

Functional tests for Aerospike server Docker images.

MODES:
    Test from releases/    Run docker-build.sh first, then test built images.
                           One version or lineage per run (e.g. 7.1 or 8.1).
                           To test multiple lineages, run the script once per lineage.
    Test specific image    Use -i to test any image by tag (local or remote)

OPTIONS:
    -i, --image IMAGE    Test a specific image by its full tag
    -e, --edition ED     Edition filter: community, enterprise, federal
                         With -i: optional, used to verify edition matches
                         Without -i: filters which images to test
    -d, --distro DIST    Distro filter: ubuntu22.04, ubuntu24.04, ubi9, ubi10
                         Prefix match: -d ubuntu (all Ubuntu), -d ubi (all UBI)
    -p, --platform PLAT  Platform: linux/amd64, linux/arm64 (single; overrides -a)
                         Default: auto-detect from host architecture
    -a, --arch ARCH      Architecture filter(s): amd64, arm64 (or x86_64, aarch64)
                         Can specify multiple: -a amd64 arm64. Test each built image for these archs.
                         Ignored when -i or -p is used.
    -c, --clean          Remove each image after its test passes (container + image)
    -h, --help           Show this help message

TESTS PERFORMED:
    1. Container starts successfully
    2. asd process is running
    3. asinfo exists in container
    4. asinfo responds with "ok"
    5. Version matches expected (if detectable)
    6. Edition matches expected (if -e specified)
    7. Default namespace 'test' exists

EXAMPLES:
    # Test a specific image (from any registry)
    $0 -i aerospike/aerospike-server-enterprise:8.1.1.0

    # Test a specific image with explicit platform
    $0 -i aerospike/aerospike-server:8.1.1.0 -p linux/arm64

    # Test a specific image and verify edition
    $0 -i myregistry/aerospike:latest -e enterprise

    # Test images built by docker-build.sh (from releases/ directory)
    # First: ./docker-build.sh -t 8.1 -e enterprise -d ubuntu24.04
    # Then:
    $0 8.1 -e enterprise -d ubuntu24.04

    # Test all built images for a lineage
    $0 8.1

    # Test only specific architecture(s) of built images
    $0 8.1 -a amd64
    $0 8.1 -a amd64 arm64

    # Test and cleanup images after
    $0 8.1 -e enterprise -c

    # Test specific version (uses releases/ directory)
    $0 8.1.1.0-start-108 -e enterprise -d ubuntu24.04

PREREQUISITES:
    For testing from releases/:
      - Run docker-build.sh first to generate and build images
      - Images must be loaded locally (use -t mode in docker-build.sh)

    For testing specific images (-i):
      - Image must be accessible (local or pullable from registry)
EOF
}

function parse_args() {
    VERSION_OR_LINEAGE=""
    SPECIFIC_IMAGE=""
    EDITION=""
    DISTRIBUTION=""
    PLATFORM=""
    PLATFORM_EXPLICIT="false"
    declare -ga ARCH_FILTERS=()
    CLEAN="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -i | --image)
            SPECIFIC_IMAGE="$2"
            shift 2
            ;;
        -e | --edition)
            EDITION="$2"
            shift 2
            ;;
        -d | --distro)
            DISTRIBUTION="$2"
            shift 2
            ;;
        -p | --platform)
            PLATFORM="$2"
            PLATFORM_EXPLICIT="true"
            shift 2
            ;;
        -a | --arch)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                ARCH_FILTERS+=("$1")
                shift
            done
            ;;
        -c | --clean)
            CLEAN="true"
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
            VERSION_OR_LINEAGE="$1"
            shift
            ;;
        esac
    done

    # Default platform to host architecture
    if [ -z "${PLATFORM}" ]; then
        local arch
        arch=$(uname -m)
        case "${arch}" in
        x86_64) PLATFORM="linux/amd64" ;;
        arm64 | aarch64) PLATFORM="linux/arm64" ;;
        *) PLATFORM="linux/amd64" ;;
        esac
    fi

    # Build PLATFORMS_LIST for test_from_releases: -p wins (single), else -a (multiple), else default (single)
    declare -ga PLATFORMS_LIST=()
    if [ "${PLATFORM_EXPLICIT}" = "true" ]; then
        PLATFORMS_LIST=("${PLATFORM}")
    elif [ ${#ARCH_FILTERS[@]} -gt 0 ]; then
        for f in "${ARCH_FILTERS[@]}"; do
            case "${f}" in
            amd64 | x86_64) PLATFORMS_LIST+=("linux/amd64") ;;
            arm64 | aarch64) PLATFORMS_LIST+=("linux/arm64") ;;
            *) log_warn "Unknown arch filter: $f (use amd64 or arm64)" ;;
            esac
        done
        if [ ${#PLATFORMS_LIST[@]} -eq 0 ]; then
            PLATFORMS_LIST=("${PLATFORM}")
        fi
    else
        PLATFORMS_LIST=("${PLATFORM}")
    fi

    if [ -z "${SPECIFIC_IMAGE}" ] && [ -z "${VERSION_OR_LINEAGE}" ]; then
        log_warn "Either version/lineage or -i IMAGE is required"
        usage
        exit 1
    fi
}

function get_version_from_dockerfile() {
    local dockerfile="releases/$1/$2/$3/Dockerfile"
    [ -f "${dockerfile}" ] || return 1
    sed -n 's/.*org.opencontainers.image.version="\([^"]*\)".*/\1/p' "${dockerfile}" | head -1 | tr -d '\r\n'
}

# Get image tag from bake-multi.hcl if present (matches what docker-build.sh -t produced, including -r registry)
function get_image_tag_from_bake() {
    local lineage=$1 edition=$2 distro=$3 arch=$4
    local bake_file="bake-multi.hcl"
    [ -f "${bake_file}" ] || return 1
    local tag_base="${lineage//./-}_${edition}_${distro//./-}_${arch}"
    sed -n "/target \"${tag_base}\"/,/^}/p" "${bake_file}" | sed -n 's/.*tags=\["\([^"]*\)".*/\1/p' | head -1
}

function run_docker() {
    log_info "Starting container..."
    if [ -n "${PLATFORM}" ]; then
        docker run -td --name "${CONTAINER}" -e "DEFAULT_TTL=30d" --platform="${PLATFORM}" "${IMAGE_TAG}"
    else
        docker run -td --name "${CONTAINER}" -e "DEFAULT_TTL=30d" "${IMAGE_TAG}"
    fi
}

function try() {
    local attempts=$1
    shift
    for ((i = 0; i < attempts; i++)); do
        if eval "${*@Q}" 2>/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}

function check_container() {
    local version=$1
    local expected_edition=$2
    local expected_arch=${3:-}

    log_info "Verifying container..."

    # Check running
    if [ "$(docker container inspect -f '{{.State.Status}}' "${CONTAINER}")" != "running" ]; then
        log_failure "Container failed to start"
        docker logs "${CONTAINER}" 2>&1 | tail -20
        exit 1
    fi
    log_success "Container running"

    # Check asinfo exists before using it (used for "asd running" check when procps not in image)
    local have_asinfo=false
    if docker exec -t "${CONTAINER}" bash -c 'command -v asinfo' >/dev/null 2>&1; then
        log_success "asinfo found"
        have_asinfo=true
    else
        log_warn "asinfo not found in container; skipping asinfo-based checks"
    fi

    # Verify asd is running: prefer asinfo -v status (works without procps); else pgrep; else TCP port 3000
    local asd_ok=false
    if [ "${have_asinfo}" = "true" ]; then
        if try 15 docker exec -t "${CONTAINER}" bash -c 'asinfo -v status' 2>/dev/null | grep -qE "^ok"; then
            asd_ok=true
        fi
    fi
    if [ "${asd_ok}" = false ] && try 15 docker exec -t "${CONTAINER}" bash -c 'pgrep -x asd' >/dev/null 2>&1; then
        asd_ok=true
    fi
    if [ "${asd_ok}" = false ] && try 15 docker exec -t "${CONTAINER}" bash -c 'echo >/dev/tcp/127.0.0.1/3000' 2>/dev/null; then
        asd_ok=true
    fi
    if [ "${asd_ok}" = false ]; then
        log_failure "asd not running"
        docker logs "${CONTAINER}" 2>&1 | tail -30
        exit 1
    fi
    log_success "asd running"

    if [ "${have_asinfo}" = "true" ]; then
        if ! docker exec -t "${CONTAINER}" bash -c 'asinfo -v status' 2>/dev/null | grep -qE "^ok"; then
            log_failure "asinfo not responding"
            exit 1
        fi
        log_success "asinfo responding"

        # Check version (optional)
        local base_version
        base_version=$(echo "${version}" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
        if [ -n "${base_version}" ]; then
            local build
            build=$(docker exec -t "${CONTAINER}" bash -c 'asinfo -v build' 2>/dev/null | tr -d '\r' || true)
            if [[ "${build}" == ${base_version}* ]]; then
                log_success "Version: ${build}"
            else
                log_info "Version: ${build}"
            fi
        fi

        # Check edition
        local actual_edition
        actual_edition=$(docker exec -t "${CONTAINER}" bash -c 'asinfo -v edition' 2>/dev/null | tr -d '\r' || true)

        if [ -n "${expected_edition}" ]; then
            # Edition was specified - verify it matches
            if [[ "${actual_edition,,}" == *"${expected_edition,,}"* ]]; then
                log_success "Edition: ${actual_edition}"
            else
                log_warn "Edition mismatch! Expected: ${expected_edition}, Got: ${actual_edition}"
            fi
        else
            # Edition not specified - just show it
            log_info "Edition: ${actual_edition}"
        fi

        # Report architecture (expected arch or container uname -m) — after Edition
        if [ -n "${expected_arch}" ] && [ "${expected_arch}" != "(host)" ]; then
            log_success "Architecture: ${expected_arch}"
        else
            local container_arch
            container_arch=$(docker exec -t "${CONTAINER}" uname -m 2>/dev/null | tr -d '\r\n' || echo "?")
            log_success "Architecture: ${container_arch}"
        fi

        # Check namespace
        if docker exec -t "${CONTAINER}" bash -c 'asinfo -v namespaces' 2>/dev/null | grep -q "test"; then
            log_success "Namespace 'test' exists"
        fi
    else
        # No asinfo — still report architecture
        if [ -n "${expected_arch}" ] && [ "${expected_arch}" != "(host)" ]; then
            log_success "Architecture: ${expected_arch}"
        else
            local container_arch
            container_arch=$(docker exec -t "${CONTAINER}" uname -m 2>/dev/null | tr -d '\r\n' || echo "?")
            log_success "Architecture: ${container_arch}"
        fi
    fi
}

# Optional first arg: "full" = also remove image when CLEAN=true (use after test).
# No arg = container only (use before run_docker so we don't remove the image we're about to run).
function cleanup() {
    docker stop "${CONTAINER}" 2>/dev/null || true
    docker rm -f "${CONTAINER}" 2>/dev/null || true
    if [ "${1:-}" = "full" ] && [ "${CLEAN}" = "true" ]; then
        docker rmi -f "${IMAGE_TAG}" 2>/dev/null || true
    fi
}

function test_specific_image() {
    IMAGE_TAG="${SPECIFIC_IMAGE}"
    CONTAINER="aerospike-test-$$"

    local arch_display="${PLATFORM#*/}"
    [ -z "${arch_display}" ] && arch_display="(host)"
    log_info "====== Testing: ${IMAGE_TAG} ======"
    log_info "  Platform: ${PLATFORM}"
    log_info "  Architecture: ${arch_display}"
    [ -n "${EDITION}" ] && log_info "  Expected edition: ${EDITION}"
    echo ""

    local version
    version=$(echo "${IMAGE_TAG}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9-]+)?' || echo "")

    trap 'cleanup full' EXIT
    # Remove any previous container only
    cleanup
    run_docker
    check_container "${version}" "${EDITION}" "${arch_display}"
    cleanup full

    echo ""
    log_success "====== Test passed! ======"
}

function test_from_releases() {
    local lineage
    if [[ "${VERSION_OR_LINEAGE}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        lineage=$(get_lineage_from_version "${VERSION_OR_LINEAGE}")
    else
        lineage="${VERSION_OR_LINEAGE}"
    fi

    local arch_list=""
    for p in "${PLATFORMS_LIST[@]}"; do arch_list="${arch_list} ${p#*/}"; done
    arch_list=${arch_list# }
    log_info "Testing: ${lineage}"
    [ -n "${EDITION}" ] && log_info "  Edition: ${EDITION}"
    [ -n "${DISTRIBUTION}" ] && log_info "  Distro: ${DISTRIBUTION}"
    log_info "  Platform(s): ${PLATFORMS_LIST[*]}"
    log_info "  Architecture(s): ${arch_list}"
    echo ""

    local editions=${EDITION:-$(support_editions)}
    local distros
    distros=$(support_distros_matching "${lineage}" "${DISTRIBUTION:-}")
    local tested=0
    local skip_no_dir=0
    local skip_no_image=0

    # Report which release dirs exist (so user sees why only one may be tested)
    local existing_dirs=""
    for edition in ${editions}; do
        for distro in ${distros}; do
            [ -d "releases/${lineage}/${edition}/${distro}" ] && existing_dirs="${existing_dirs} ${edition}/${distro}"
        done
    done
    existing_dirs=${existing_dirs# }
    log_info "Release dirs for ${lineage}: ${existing_dirs:-none}"
    echo ""

    for edition in ${editions}; do
        for distro in ${distros}; do
            local dir="releases/${lineage}/${edition}/${distro}"
            if [ ! -d "${dir}" ]; then
                skip_no_dir=$((skip_no_dir + 1))
                log_info "Skipping ${edition}/${distro}: no releases/ directory"
                continue
            fi

            local version
            version=$(get_version_from_dockerfile "${lineage}" "${edition}" "${distro}") || continue
            version=$(printf '%s' "${version}" | tr -d '\r\n\t ')
            [ -z "${version}" ] && continue

            for plat in "${PLATFORMS_LIST[@]}"; do
                local arch=${plat#*/}
                # Federal only supports amd64
                if [ "${edition}" = "federal" ] && [ "${arch}" = "arm64" ]; then
                    continue
                fi

                IMAGE_TAG=$(get_image_tag_from_bake "${lineage}" "${edition}" "${distro}" "${arch}") || true
                if [ -z "${IMAGE_TAG}" ]; then
                    local img_base="aerospike/aerospike-server"
                    [ "${edition}" != "community" ] && img_base+="-${edition}"
                    # Match docker-build.sh: single-distro build uses version-arch, multi uses version-distro-arch
                    IMAGE_TAG="${img_base}:${version}-${distro}-${arch}"
                    if ! docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
                        IMAGE_TAG="${img_base}:${version}-${arch}"
                    fi
                fi

                CONTAINER="aerospike-test-${edition}-${distro//./}-${arch}-$$"

                log_info "====== Testing: ${IMAGE_TAG} (${plat}) ======"

                if ! docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
                    skip_no_image=$((skip_no_image + 1))
                    log_warn "Skipping ${edition}/${distro}/${arch}: image not found locally"
                    continue
                fi

                PLATFORM="${plat}"
                trap 'cleanup full' EXIT
                # Remove any previous container only
                cleanup
                run_docker
                check_container "${version}" "${edition}" "${arch}"
                cleanup full

                tested=$((tested + 1))
                echo ""
            done
        done
    done

    if [ "${tested}" -eq 0 ]; then
        log_warn "No images found. Run docker-build.sh first."
        exit 1
    fi
    log_info "Summary: ${tested} tested, ${skip_no_dir} skipped (no releases/ dir), ${skip_no_image} skipped (image not built)"
    log_success "====== All ${tested} test(s) passed! ======"
}

function main() {
    parse_args "$@"
    if [ -n "${SPECIFIC_IMAGE}" ]; then
        test_specific_image
    else
        test_from_releases
    fi
}

main "$@"
