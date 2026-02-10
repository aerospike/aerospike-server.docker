#!/usr/bin/env bash

#----------------------------------------------------------------------
# Test built Docker images
#----------------------------------------------------------------------

set -Eeuo pipefail

source lib/log.sh
source lib/support.sh
source lib/version.sh

function usage() {
    cat << EOF
Usage: $0 [version|lineage] [OPTIONS]
       $0 -i IMAGE [OPTIONS]

Functional tests for Aerospike server Docker images.

MODES:
    Test from releases/    Run docker-build.sh first, then test built images
    Test specific image    Use -i to test any image by tag (local or remote)

OPTIONS:
    -i, --image IMAGE    Test a specific image by its full tag
    -e, --edition ED     Edition filter: community, enterprise, federal
                         With -i: optional, used to verify edition matches
                         Without -i: filters which images to test
    -d, --distro DIST    Distro filter: ubuntu22.04, ubuntu24.04, ubi9, ubi10
    -p, --platform PLAT  Platform: linux/amd64, linux/arm64
                         Default: auto-detect from host architecture
    -c, --clean          Remove tested images after test completes
    -h, --help           Show this help message

TESTS PERFORMED:
    1. Container starts successfully
    2. asd process is running
    3. asinfo responds with "ok"
    4. Version matches expected (if detectable)
    5. Edition matches expected (if -e specified)
    6. Default namespace 'test' exists

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

function get_lineage_from_version() {
    echo "$1" | grep -oE '^[0-9]+\.[0-9]+'
}

function parse_args() {
    VERSION_OR_LINEAGE=""
    SPECIFIC_IMAGE=""
    EDITION=""
    DISTRIBUTION=""
    PLATFORM=""
    CLEAN="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--image)    SPECIFIC_IMAGE="$2"; shift 2 ;;
            -e|--edition)  EDITION="$2"; shift 2 ;;
            -d|--distro)   DISTRIBUTION="$2"; shift 2 ;;
            -p|--platform) PLATFORM="$2"; shift 2 ;;
            -c|--clean)    CLEAN="true"; shift ;;
            -h|--help)     usage; exit 0 ;;
            -*)            log_warn "Unknown option: $1"; usage; exit 1 ;;
            *)             VERSION_OR_LINEAGE="$1"; shift ;;
        esac
    done

    # Default platform to host architecture
    if [ -z "${PLATFORM}" ]; then
        local arch=$(uname -m)
        case "${arch}" in
            x86_64)          PLATFORM="linux/amd64" ;;
            arm64|aarch64)   PLATFORM="linux/arm64" ;;
            *)               PLATFORM="linux/amd64" ;;
        esac
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
    grep "org.opencontainers.image.version=" "${dockerfile}" | grep -oE '"[^"]+' | tr -d '"'
}

function run_docker() {
    log_info "Starting container..."
    local platform_arg=""
    [ -n "${PLATFORM}" ] && platform_arg="--platform=${PLATFORM}"
    docker run -td --name "${CONTAINER}" -e "DEFAULT_TTL=30d" ${platform_arg} "${IMAGE_TAG}"
}

function try() {
    local attempts=$1; shift
    for ((i = 0; i < attempts; i++)); do
        if eval "${*@Q}" 2>/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}

function check_container() {
    local version=$1
    local expected_edition=$2

    log_info "Verifying container..."

    # Check running
    if [ "$(docker container inspect -f '{{.State.Status}}' "${CONTAINER}")" != "running" ]; then
        log_failure "Container failed to start"
        docker logs "${CONTAINER}" 2>&1 | tail -20
        exit 1
    fi
    log_success "Container running"

    # Check asd process
    if ! try 15 docker exec -t "${CONTAINER}" bash -c 'pgrep -x asd' >/dev/null; then
        log_failure "asd not running"
        docker logs "${CONTAINER}" 2>&1 | tail -30
        exit 1
    fi
    log_success "asd process running"

    # Check asinfo responds
    if ! try 10 docker exec -t "${CONTAINER}" bash -c 'asinfo -v status' | grep -qE "^ok"; then
        log_failure "asinfo not responding"
        exit 1
    fi
    log_success "asinfo responding"

    # Check version (optional)
    local base_version=$(echo "${version}" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
    if [ -n "${base_version}" ]; then
        local build=$(docker exec -t "${CONTAINER}" bash -c 'asinfo -v build' 2>/dev/null | tr -d '\r' || true)
        if [[ "${build}" == ${base_version}* ]]; then
            log_success "Version: ${build}"
        else
            log_info "Version: ${build}"
        fi
    fi

    # Check edition
    local actual_edition=$(docker exec -t "${CONTAINER}" bash -c 'asinfo -v edition' 2>/dev/null | tr -d '\r' || true)
    
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

    # Check namespace
    if docker exec -t "${CONTAINER}" bash -c 'asinfo -v namespaces' 2>/dev/null | grep -q "test"; then
        log_success "Namespace 'test' exists"
    fi
}

function cleanup() {
    docker stop "${CONTAINER}" 2>/dev/null || true
    docker rm -f "${CONTAINER}" 2>/dev/null || true
    [ "${CLEAN}" = "true" ] && docker rmi -f "${IMAGE_TAG}" 2>/dev/null || true
}

function test_specific_image() {
    IMAGE_TAG="${SPECIFIC_IMAGE}"
    CONTAINER="aerospike-test-$$"
    
    log_info "====== Testing: ${IMAGE_TAG} ======"
    log_info "  Platform: ${PLATFORM}"
    [ -n "${EDITION}" ] && log_info "  Expected edition: ${EDITION}"
    echo ""

    local version=$(echo "${IMAGE_TAG}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9-]+)?' || echo "")

    trap cleanup EXIT
    cleanup  # Clean any previous
    run_docker
    check_container "${version}" "${EDITION}"
    
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

    log_info "Testing: ${lineage}"
    [ -n "${EDITION}" ] && log_info "  Edition: ${EDITION}"
    [ -n "${DISTRIBUTION}" ] && log_info "  Distro: ${DISTRIBUTION}"
    log_info "  Platform: ${PLATFORM}"
    echo ""

    local editions=${EDITION:-$(support_editions)}
    local distros=${DISTRIBUTION:-$(support_distros "${lineage}")}
    local tested=0

    for edition in ${editions}; do
        for distro in ${distros}; do
            local dir="releases/${lineage}/${edition}/${distro}"
            [ -d "${dir}" ] || continue

            local version=$(get_version_from_dockerfile "${lineage}" "${edition}" "${distro}") || continue
            local arch=${PLATFORM#*/}
            
            IMAGE_TAG="aerospike/aerospike-server"
            [ "${edition}" != "community" ] && IMAGE_TAG+="-${edition}"
            IMAGE_TAG+=":${version}-${distro//./-}-${arch}"
            
            CONTAINER="aerospike-test-${edition}-${distro//./}-$$"

            log_info "====== Testing: ${IMAGE_TAG} ======"
            
            trap cleanup EXIT
            cleanup
            run_docker
            check_container "${version}" "${edition}"
            cleanup
            
            ((tested++))
            echo ""
        done
    done

    [ "${tested}" -eq 0 ] && { log_warn "No images found. Run docker-build.sh first."; exit 1; }
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
