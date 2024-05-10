#!/usr/bin/env bash

#----------------------------------------------------------------------
# Sample:
#   All editions and distributions: ./test.sh --all
#   enterprise, ubuntu20 with cleanup: ./test.sh -e enterpise -d ubuntu20 -c
#----------------------------------------------------------------------

set -Eeuo pipefail

source lib/log.sh
source lib/support.sh
source lib/verbose_call.sh
source lib/version.sh

IMAGE_TAG=
CONTAINER=

function usage() {
    cat <<EOF
Usage: $0 [-e|--edition EDITION] [-d|--distro DISTRIBUTION] [-c|--clean] [-h|--help]

    -e|--edition EDITION: community, enterprise, federal.
    -d|--distro DISTRIBUTION: ubuntu20.
    -c|--clean: cleanup the images after the test.
    -h|--help: this help.
EOF
}

function parse_args() {
    CLEAN="false"
    EDITION=
    DISTRIBUTION=

    PARSED_ARGS=$(getopt -a -n test -o che:d:p: --long clean,help,edition:,distro:,platform: -- "$@")
    VALID_ARGS=$?

    if [ "${VALID_ARGS}" != "0" ]; then
        usage
    fi

    eval set -- "${PARSED_ARGS}"
    while true; do
        case "$1" in
        -c | --clean)
            CLEAN="true"
            shift
            ;;
        -e | --edition)
            EDITION=$2
            shift 2
            ;;
        -d | --distro)
            DISTRIBUTION=$2
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -h)
            usage
            exit 0
            ;;
        *)
            log_warn "Unexpected option: $1"
            usage
            exit 1
            ;;
        esac
    done
}

function run_docker() {
    version=$1

    log_info "------ Running docker image ${IMAGE_TAG} ..."

    if [ "${EDITION}" = "community" ] || version_compare_gt "${version}" "6.1"; then
        verbose_call docker run -td --name "${CONTAINER}" "${PLATFORM/#/"--platform="}" \
            "${IMAGE_TAG}"
    else
        # Must supply a feature key when version is prior to 6.1.
        verbose_call docker run -td --name "${CONTAINER}" "${PLATFORM/#/"--platform="}" \
            -v "/$(pwd)/res/":/asfeat/ -e "FEATURE_KEY_FILE=/asfeat/eval_features.conf" \
            "${IMAGE_TAG}"
    fi
}

function try() {
    attempts=$1 # 1 second sleep between attempts.
    shift
    cmd="${*@Q}"

    for ((i = 0; i < attempts; i++)); do
        log_debug "Attempt ${i} for ${cmd}" >&2

        if eval "${cmd}"; then
            return 0
        fi

        sleep 1
    done

    return 1
}

function check_container() {
    local version=$1

    log_info "------ Verifying docker container ..."

    if [ "$(docker container inspect -f '{{.State.Status}}' "${CONTAINER}")" == "running" ]; then
        log_success "Container ${CONTAINER} started and running"
    else
        log_failure "**Container ${CONTAINER} failed to start**"
        exit 1
    fi

    container_platform="$(docker exec -t "${CONTAINER}" bash -c 'stty -onlcr && uname -m')"
    expected_platform="$(support_platform_to_arch "${PLATFORM}")"

    if [ "${container_platform}" = "${expected_platform}" ]; then
        log_success "Container platform is expected platform '${expected_platform}'"
    else
        log_failure "**Container platform '${container_platform}' does not match expected platform '${expected_platform}'**"
        exit 1
    fi

    if try 10 docker exec -t "${CONTAINER}" bash -c 'pgrep -x asd' >/dev/null; then
        log_success "Aerospike database is running"
    else
        log_failure "**Aerospike database is not running**"
        exit 1
    fi

    if try 5 docker exec -t "${CONTAINER}" bash -c 'asinfo -v status' | grep -qE "^ok"; then
        log_success "(asinfo) Aerospike database is responding"
    else
        log_failure "**(asinfo) Aerospike database is not responding**"
        exit 1
    fi

    build=$(try 5 docker exec -t "${CONTAINER}" bash -c 'asadm -e "enable; asinfo -v build"' | grep -oE "^${version}")

    if [ -n "${build}" ]; then
        log_success "(asadm) Aerospike database has correct version - '${build}'"
    else
        log_failure "**(asadm) Aerospike database has incorrect version - '${build}'**"
        exit 1
    fi

    edition=$(try 5 docker exec -t "${CONTAINER}" bash -c 'asadm -e "enable; asinfo -v edition"' | grep -oE "^Aerospike ${EDITION^} Edition")

    if [ -n "${edition}" ]; then
        log_success "(asadm) Aerospike database has correct edition - '${edition}'"
    else
        log_failure "**(asadm) Aerospike database has incorrect edition - '${edition}'**"
        exit 1
    fi

    if version_compare_gt "${version}" "6.2"; then
        tool="asinfo"
        namespace=$(try 5 docker exec -t "${CONTAINER}" bash -c 'asinfo -v namespaces' | grep -o "test")
    else
        tool="aql"
        namespace=$(try 5 docker exec -t "${CONTAINER}" bash -c 'aql -o raw <<<"SHOW namespaces" 2>/dev/null' | grep "namespaces: \"test\"")
    fi

    if [ -n "${namespace}" ]; then
        log_success "(${tool}) Aerospike database has namespace 'test' - '${namespace}'"
    else
        log_failure "**(${tool}) Aerospike database does not have namespace 'test' - '${namespace}'"
    fi

    log_info "------ Verify docker image completed successfully"
}

function try_stop_docker() {
    log_info "------ Stop and remove containers form prior failed run"

    if verbose_call docker stop "${CONTAINER}"; then
        verbose_call docker rm -f "${CONTAINER}"
    fi

    log_info "------ Stop and remove containers form prior failed run complete"
}

function clean_docker() {
    log_info "------ Cleaning up old containers ..."
    verbose_call docker stop "${CONTAINER}"
    verbose_call docker rm -f "${CONTAINER}"
    log_info "------ Cleaning up old containers complete"

    if [ "${CLEAN}" = "true" ]; then
        log_info "------ Cleaning up old images ..."
        verbose_call docker rmi -f "$(docker images "${IMAGE_TAG}" -a -q | sort | uniq)"
        log_info "------ Cleaning up old images complete"
    fi
}

function test_current_edition_distro() {
    local version
    version="$(get_version_from_dockerfile "${DISTRIBUTION}" "${EDITION}")"
    CONTAINER="aerospike-server-${EDITION}"
    local platform_list
    IFS=' ' read -r -a platform_list <<<"$(support_platforms_for_asd "${version}" "${EDITION}")"

    for platform in "${platform_list[@]}"; do
        short_platform=${platform#*/}
        IMAGE_TAG="aerospike/aerospike-server-${EDITION}-${short_platform}:${version}"
        PLATFORM=${platform}
        try_stop_docker
        run_docker "${version}"
        check_container "${version}"
        clean_docker
    done
}

function main() {
    parse_args "$@"

    local edition_list=("${EDITION}")

    if [ -z "${EDITION}" ]; then
        readarray -t edition_list < <(find community enterprise federal -name Dockerfile -type f | cut -d/ -f1)
    fi

    log_info "------ Testing editions: '${edition_list[*]}'"

    for edition in "${edition_list[@]}"; do
        local distribution_list=("${DISTRIBUTION}")

        if [ -z "${DISTRIBUTION}" ]; then
            readarray -t distribution_list < <(find "${edition}"/* -maxdepth 0 -type d | cut -d/ -f2)
        fi

        for distribution in "${distribution_list[@]}"; do
            EDITION=$edition
            DISTRIBUTION=$distribution

            log_info "------ Testing for edition=${EDITION} Distribution=${DISTRIBUTION}"

            test_current_edition_distro
        done
    done
}

main "$@"
