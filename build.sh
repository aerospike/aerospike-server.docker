#!/usr/bin/env bash

#-------------------------------------------------------------------------
# build images for test (by the script test.sh) or release (push to docker registry)
# Samples:
#   build and push to docker repo: ./build.sh -p
#   build all images for test: ./build.sh -t
#-----------------------------------------------------------------------

set -Eeuo pipefail

source lib/log.sh
source lib/support.sh
source lib/verbose_call.sh

function usage() {
    cat <<EOF
Usage: $0 -h -d <linux distro> -e <server edition>

    -h display this help.
    -t build for invoking test in test.sh
    -p build for release/push to dockerhub
EOF
}

function parse_args() {
    g_test_build='false'
    g_push_build='false'

    while getopts "htp" opt; do
        case "${opt}" in
        h)
            usage
            exit 0
            ;;
        t)
            g_test_build='true'
            ;;
        p)
            g_push_build='true'
            ;;
        *)
            log_warn "** Invalid argument **"
            usage
            exit 1
            ;;
        esac
    done

    shift $((OPTIND - 1))

    log_info "g_test_build: '${g_test_build}'"
    log_info "g_push_build: '${g_push_build}'"

    if [ "${g_test_build}" = "false" ] && [ "${g_push_build}" = "false" ]; then
        log_warn "Must provide either '-t' or '-p' option"
        exit 1
    fi

    if [ "${g_test_build}" = "true" ] && [ "${g_push_build}" = "true" ]; then
        log_warn "Must provide either '-t' or '-p' option, not both"
        exit 1
    fi
}

function main() {
    parse_args "$@"

    local targets=

    if [ "${g_test_build}" = "true" ]; then
        targets="test"
    elif [ "${g_push_build}" = "true" ]; then
        targets="push"
    fi

    local params=

    if [ "${g_test_build}" = "true" ]; then
        params="--load"
    elif [ "${g_push_build}" = "true" ]; then
        params="--push"
    fi

    for version_path in images/*; do
        log_info "main() - build ${version_path}"

        local bake_file="${version_path}/bake.hcl"
        local revision=
        revision="$(git rev-parse HEAD)"
        local created=
        created="$(date --rfc-3339=seconds)"

        verbose_call docker buildx bake --pull --progress plain ${params} \
                     --set "\*.labels.org.opencontainers.image.revision=\"${revision}\"" \
                     --set "\*.labels.org.opencontainers.image.created=\"${created}\"" \
                     --file "${bake_file}" "${targets}"
    done
}

main "$@"
