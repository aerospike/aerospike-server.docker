#!/usr/bin/env bash

#----------------------------------------------------------------------
# Sample:
#   All editions and distributions: ./test.sh --all
#   enterprise, debian11 with cleanup: ./test.sh -e enterpise -d debian11 -c
#----------------------------------------------------------------------

set -Eeuo pipefail

source lib/globals.sh
source lib/log.sh
source lib/support.sh
source lib/verbose_call.sh
source lib/version.sh

function usage() {
    cat <<EOF
Usage: $0 [-c|--clean] [-h|--help]

    -c cleanup the images after the test.
    -h display this help.
EOF
}

function parse_args() {
    g_clean="false"

    while getopts "ch" opt; do
        case "${opt}" in
        c)
            g_clean="true"
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            log_warn "** Invalid argument **"
            usage
            exit 1
            ;;
        esac
    done
}

function run_docker() {
    local version=$1
    local edition=$2
    local platform=$3
    local container=$4
    local image_tag=$5

    log_info "running docker image '${image_tag}'"

    if [ "${edition}" = "community" ] || version_compare_gt "${version}" "6.1"; then
        verbose_call docker run -td --name "${container}" \
            "${platform/#/"--platform="}" "${image_tag}"
    else
        # Must supply a feature key when version is prior to 6.1.
        verbose_call docker run -td --name "${container}" \
            "${platform/#/"--platform="}" -v "$(pwd)/${g_data_res_dir}/":/asfeat/ \
            -e "FEATURE_KEY_FILE=/asfeat/eval_features.conf" "${image_tag}"
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
    local edition=$2
    local platform=$3
    local container=$4

    log_info "verifying container '${container}' version '${version}' platform '${platform}' ..."

    if [ "$(docker container inspect -f '{{.State.Status}}' "${container}")" == "running" ]; then
        log_success "Container '${container}' started and running"
    else
        log_failure "**Container '${container}' failed to start**"
        exit 1
    fi

    container_platform="$(docker exec -t "${container}" bash -c \
        'stty -onlcr && uname -m')"
    expected_platform="$(support_platform_to_arch "${platform}")"

    if [ "${container_platform}" = "${expected_platform}" ]; then
        log_success "Container platform is expected platform '${expected_platform}'"
    else
        log_failure "**Container platform '${container_platform}' does not match expected platform '${expected_platform}'**"
        exit 1
    fi

    if try 10 docker exec -t "${container}" bash -c 'pgrep -x asd' >/dev/null; then
        log_success "Aerospike database is running"
    else
        log_failure "**Aerospike database is not running**"
        exit 1
    fi

    if try 5 docker exec -t "${container}" bash -c 'asinfo -v status' | grep -qE "^ok"; then
        log_success "(asinfo) Aerospike database is responding"
    else
        log_failure "**(asinfo) Aerospike database is not responding**"
        exit 1
    fi

    build=$(try 5 docker exec -t "${container}" bash -c \
        'asadm -e "enable; asinfo -v build"' | grep -oE "^${version}")

    if [ -n "${build}" ]; then
        log_success "(asadm) Aerospike database has correct version - '${build}'"
    else
        log_failure "**(asadm) Aerospike database has incorrect version - '${build}'**"
        exit 1
    fi

    container_edition=$(try 5 docker exec -t "${container}" bash -c \
        'asadm -e "enable; asinfo -v edition"' | grep -oE "^Aerospike ${edition^} Edition")

    if [ -n "${container_edition}" ]; then
        log_success "(asadm) Aerospike database has correct edition - '${container_edition}'"
    else
        log_failure "**(asadm) Aerospike database has incorrect edition - '${container_edition}'**"
        exit 1
    fi

    if version_compare_gt "${version}" "6.2"; then
        tool="asinfo"
        namespace=$(try 5 docker exec -t "${container}" bash -c \
            'asinfo -v namespaces' | grep -o "test")
    else
        tool="aql"
        namespace=$(try 5 docker exec -t "${container}" bash -c \
            'aql -o raw <<<"SHOW namespaces" 2>/dev/null' | grep "namespaces: \"test\"")
    fi

    if [ -n "${namespace}" ]; then
        log_success "(${tool}) Aerospike database has namespace 'test' - '${namespace}'"
    else
        log_failure "**(${tool}) Aerospike database does not have namespace 'test' - '${namespace}'"
    fi

    log_info "verify docker image completed successfully"
}

function try_stop_docker() {
    local container=$1

    log_info "stop and remove containers '${container}' form prior failed run ..."

    if verbose_call docker stop "${container}"; then
        verbose_call docker rm -f "${container}"
    fi

    log_info "stop and remove containers form prior failed run complete"
}

function clean_docker() {
    local container=$1
    local image_tag=$2

    log_info "cleaning up old containers '${container}' ..."
    verbose_call docker stop "${container}"
    verbose_call docker rm -f "${container}"
    log_info "cleaning up old containers complete"

    if [ "${g_clean}" = "true" ]; then
        log_info "cleaning up old images '${image_tag}' ..."
        verbose_call docker rmi -f "$(docker images "${image_tag}" -a -q | sort | uniq)"
        log_info "cleaning up old images complete"
    fi
}

function main() {
    parse_args "$@"

    for version_path in images/*; do
        local short_version=
        short_version="$(basename "${version_path}")"

        support_source_config "${version_path}" ""

        for edition in "${c_editions[@]}"; do
            local container="aerospike-server-${edition}"
            local edition_config="${version_path}/config_${edition}.sh"

            support_source_config "${version_path}" "${edition}"

            for distro in "${c_distros[@]}"; do
                local version
                version="$(get_version_from_dockerfile "${version_path}" "${distro}" "${edition}")"

                for platform in "${c_platforms[@]}"; do
                    local short_platform=
                    short_platform="$(basename "${platform}")"
                    local image_tag="aerospike/aerospike-server-${edition}-${short_platform}:${short_version}-${distro}"

                    try_stop_docker "${container}"
                    run_docker "${version}" "${edition}" "${platform}" "${container}" "${image_tag}"
                    check_container "${version}" "${edition}" "${platform}" "${container}" "${image_tag}"
                    clean_docker "${container}" "${image_tag}"
                done
            done
        done
    done
}

main "$@"
