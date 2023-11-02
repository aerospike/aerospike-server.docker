#!/usr/bin/env bash

#-------------------------------------------------------------------------
# build images for test (by the script test.sh) or release (push to docker registry)
# Samples:
#   build and push to docker repo: ./build.sh -p
#   build all images for test: ./build.sh -t
#-----------------------------------------------------------------------

set -Eeuo pipefail

source lib/globals.sh
source lib/log.sh
source lib/support.sh
source lib/verbose_call.sh
source lib/version.sh

g_container_release=1 # FIXME - may go away.

function usage() {
    cat <<EOF
Usage: $0 -h -d

    -d dry run
    -h display this help.
    -p build for release/push to dockerhub
    -t build for invoking test in test.sh
EOF
}

function parse_args() {
    g_dry_run='false'
    g_push_build='false'
    g_test_build='false'

    while getopts "dhtp" opt; do
        case "${opt}" in
        d)
            g_dry_run='true'
            ;;
        h)
            usage
            exit 0
            ;;
        p)
            g_push_build='true'
            ;;
        t)
            g_test_build='true'
            ;;
        *)
            log_warn "** Invalid argument **"
            usage
            exit 1
            ;;
        esac
    done

    shift $((OPTIND - 1))

    log_info "g_dry_run: '${g_dry_run}'"
    log_info "g_push_build: '${g_push_build}'"
    log_info "g_test_build: '${g_test_build}'"

    if [ "${g_dry_run}" = "true" ]; then
        return
    fi

    if [ "${g_test_build}" = "false" ] && [ "${g_push_build}" = "false" ]; then
        log_warn "Must provide either '-t' or '-p' option"
        exit 1
    fi

    if [ "${g_test_build}" = "true" ] && [ "${g_push_build}" = "true" ]; then
        log_warn "Must provide either '-t' or '-p' option, not both"
        exit 1
    fi
}

function do_bake_test_group_targets() {
    local distro=$1
    local edition=$2

    local output=""

    for platform in "${c_platforms[@]}"; do
        local short_platform=${platform#*/}
        local target_str="${edition}_${distro}_${short_platform}"

        output+="\"${target_str}\", "
    done

    echo "${output}"
}

function do_bake_group() {
    local version_path=$1
    local group=$2

    local output="#------------------------------------ ${group} -----------------------------------\n\n"

    output+="group \"${group}\" {\n    targets=["

    for edition in "${c_editions[@]}"; do
        support_source_config "${version_path}" "${edition}"

        for distro in "${c_distros[@]}"; do
            if [[ "${group}" == "test" ]]; then
                output+="$(do_bake_test_group_targets "${distro}" "${edition}")"
            elif [[ "${group}" == "push" ]]; then
                output+="\"${edition}_${distro}\", "
            else
                log_warn "unexpected group '%{group}'"
                exit 1
            fi
        done
    done

    # (Optional) Trailing comma causes no problem to Docker Buildx Bake.
    output=${output%,*}
    output+="]\n}\n"

    echo "${output}"
}

function get_product_tags() {
    local product=$1
    local distro=$2

    if [ -z "${distro}" ]; then
        local distro_prefix=
    else
        local distro_prefix="-${distro}"
    fi

    local output="\"${product}:${g_server_version}${distro_prefix}\""

    if [ -n "${g_container_release}" ]; then
        output+=", \"${product}:${g_server_version}${distro_prefix}-${g_container_release}\""
    fi

    local short_version="${version_path#*/}"

    output+=", \"${product}:${short_version}${distro_prefix}\""

    echo "${output}"
}

function do_bake_test_target() {
    local version_path=$1
    local distro=$2
    local edition=$3

    local short_version="${version_path#*/}"
    local output=""

    for platform in "${c_platforms[@]}"; do
        local short_platform="${platform#*/}"
        local target_str="${edition}_${distro}_${short_platform}"
        local product="aerospike/aerospike-server-${edition}-${short_platform}"

        output+="target \"${target_str}\" {\n"
        output+="    tags=["
        output+="$(get_product_tags "${product}" "${distro}")"
        output+="]\n"
        output+="    platforms=[\"${platform}\"]\n"
        output+="    context=\"./${version_path}/${edition}/${distro}\"\n"
        output+="}\n\n"
    done

    echo "${output}"
}

function do_bake_push_target() {
    local version_path=$1
    local distro=$2
    local edition=$3

    printf -v platforms_str '%s,' "${c_platforms[@]}"
    platforms_str="${platforms_str%,}"

    local target_str="${edition}_${distro}"
    local output="target \"${target_str}\" {\n"

    local product="aerospike/aerospike-server"

    if [ "${edition}" != "community" ]; then
        product+="-${edition}"
    fi

    output+="    tags=["

    if [ "${distro}" == "${c_distro_default}" ]; then
        output+="$(get_product_tags "${product}" "")"

        if [ "${g_latest_version}" = "${g_server_version}" ]; then
            output+=", \"${product}:latest\""
        fi

        output+=",\n    "
    fi

    output+="$(get_product_tags "${product}" "${distro}")"

    output+="]\n"
    output+="    platforms=[\"${platforms_str}\"]\n"
    output+="    context=\"./${version_path}/${edition}/${distro}\"\n"
    output+="}\n\n"

    echo "${output}"
}

function build_bake_file() {
    local version_path=$1

    local target_path=
    target_path="${g_target_dir}/$(basename "${version_path}")"
    local bake_file="${target_path}/bake.hcl"

    mkdir -p "${target_path}"

    cat <<-EOF >"${bake_file}"
# This file contains the targets for the test images.
# This file is auto-generated by the build.sh script and will be wiped out by
# the build.sh script. Please don't edit this file.
#
# Build all test/push images:
#      docker buildx bake -f ${bake_file} [test | push] --progress plain [--load | --push]
# Build selected images:
#      docker buildx bake -f ${bake_file} [target name, ...] --progress plain [--load | --push]

EOF

    local test_targets_str=""
    local push_targets_str=""

    support_source_config "${version_path}" ""

    # Generate new builds.
    for edition in "${c_editions[@]}"; do
        support_source_config "${version_path}" "${edition}"

        for distro in "${c_distros[@]}"; do
            test_targets_str+="$(do_bake_test_target "${version_path}" \
                "${distro}" "${edition}")"
            push_targets_str+="$(do_bake_push_target "${version_path}" \
                "${distro}" "${edition}")"
        done
    done

    local test_group_str
    test_group_str="$(do_bake_group "${version_path}" "test")"
    local push_group_str
    push_group_str="$(do_bake_group "${version_path}" "push")"

    {
        printf "%b\n%b" "${test_group_str}" "${test_targets_str}"
        printf "%b\n%b" "${push_group_str}" "${push_targets_str}"
    } >>"${bake_file}"
}

function main() {
    parse_args "$@"

    g_latest_version=$(find_latest_server_version)

    # Generate bake.hcl
    for version_path in "${g_images_dir}"/*; do
        local version=
        version="$(basename "${version_path}")"

        # HACK - artifacts for server need first 3 digits.
        g_server_version=$(find_latest_server_version_for_lineage "${version}.0")

        build_bake_file "${version_path}"
    done

    if [ "${g_dry_run}" = "true" ]; then
        exit 0
    fi

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

    for version_path in "${g_target_dir}"/*; do
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
