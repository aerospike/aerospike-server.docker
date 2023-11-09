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

function usage() {
    cat <<EOF
Usage: $0 [OPTION]...

    -h display this help.

    -c clean '${g_target_dir}'.
    -r build '${g_target_dir}/bake.hcl' only.

    -p build for release/push to dockerhub.
    -t build for invoking test in test.sh

    -d <distro name> as it appears in 'config.sh'. May be repeated.
    -e <Aerospike edition> as it appears in 'config.sh'. May be repeated.
    -v <two digit version> as they appear under '${g_data_config_dir}'. May be repeated.
EOF
}

function parse_args() {
    g_registry='dockerhub'
    g_dry_run='false'
    g_push_build='false'
    g_test_build='false'
    g_filter_versions=()
    g_filter_editions=()
    g_filter_distros=()

    while getopts "cd:e:hprtv:" opt; do
        case "${opt}" in
        c)
            rm -rf "${g_target_dir}"
            exit 0
            ;;
        d)
            g_filter_distros+=("${OPTARG}")
            ;;
        e)
            g_filter_editions+=("${OPTARG}")
            ;;
        h)
            usage
            exit 0
            ;;
        p)
            g_push_build='true'
            ;;
        r)
            g_dry_run='true'
            ;;
        t)
            g_test_build='true'
            ;;
        v)
            g_filter_versions+=("${OPTARG}")
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

    local temp
    temp="$(printf "'%s' " "${g_filter_versions[@]}")"
    log_info "g_filter_versions: (${temp%" "})"

    temp="$(printf "'%s' " "${g_filter_editions[@]}")"
    log_info "g_filter_editions: (${temp%" "})"

    temp="$(printf "'%s' " "${g_filter_distros[@]}")"
    log_info "g_filter_distros: (${temp%" "})"

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

function get_target_name() {
    local short_version=$1
    local distro=$2
    local edition=$3
    local short_platform=$4

    local target="${edition}_${distro}_${short_version}"

    if [ -n "${short_platform}" ]; then
        target+="_${short_platform}"
    fi

    target="${target/\./-}"

    echo "${target}"
}

function do_bake_test_group_targets() {
    local distro=$1
    local edition=$2
    local short_version=$3

    local output=""

    for platform in "${c_platforms[@]}"; do
        local short_platform=${platform#*/}
        local target_str=
        target_str="$(get_target_name "${short_version}" "${distro}" \
            "${edition}" "${short_platform}")"

        output+="\"${target_str}\", "
    done

    echo "${output}"
}

function do_bake_group() {
    local group=$1
    local group_targets=$2

    local output="#------------------------------------ ${group} -----------------------------------\n\n"

    output+="group \"${group}\" {\n    targets=["
    output+="${group_targets}"
    output+="]\n}\n"

    echo "${output}"
}

function get_product_tags() {
    local product=$1
    local version=$2
    local distro=$3

    if [ -z "${distro}" ]; then
        local distro_prefix=
    else
        local distro_prefix="-${distro}"
    fi

    local output="\"${product}:${g_server_version}${distro_prefix}\""

    output+=", \"${product}:${g_server_version}${distro_prefix}-${g_container_release}\""
    output+=", \"${product}:${version}${distro_prefix}\""

    echo "${output}"
}

function do_bake_test_target() {
    local version=$1
    local distro=$2
    local edition=$3

    local version_path="${g_images_dir}/${g_registry}/${version}"
    local output=""

    for platform in "${c_platforms[@]}"; do
        local short_platform="${platform#*/}"
        local target_str=
        target_str="$(get_target_name "${version}" "${distro}" \
            "${edition}" "${short_platform}")"
        local product="aerospike/aerospike-server-${edition}-${short_platform}"

        output+="target \"${target_str}\" {\n"
        output+="    tags=["
        output+="$(get_product_tags "${product}" "${version}" "${distro}")"
        output+="]\n"
        output+="    platforms=[\"${platform}\"]\n"
        output+="    context=\"./${version_path}/${edition}/${distro}\"\n"
        output+="}\n\n"
    done

    echo "${output}"
}

function do_bake_push_target() {
    local version=$1
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

    local version_path="${g_images_dir}/${g_registry}/${version}"

    output+="    tags=["

    if [ "${distro}" == "${c_distro_default}" ]; then
        output+="$(get_product_tags "${product}" "${version}" "")"

        if [ "${g_latest_version}" = "${g_server_version}" ]; then
            output+=", \"${product}:latest\""
        fi

        output+=",\n    "
    fi

    output+="$(get_product_tags "${product}" "${version}" "${distro}")"

    output+="]\n"
    output+="    platforms=[\"${platforms_str}\"]\n"
    output+="    context=\"./${version_path}/${edition}/${distro}\"\n"
    output+="}\n\n"

    echo "${output}"
}

function build_bake_file() {
    g_latest_version=$(find_latest_server_version)
    g_container_release="$(date --utc +%Y%m%dT%H%M%SZ -d "@${g_start_time}")"

    local test_targets_str=""
    local push_targets_str=""
    local group_test_targets=""
    local group_push_targets=""

    for version in $(support_versions "${g_registry}"); do
        if support_config_filter "${version}" "${g_filter_versions[@]}"; then
            continue
        fi

        # HACK - artifacts for server need first 3 digits.
        g_server_version=$(find_latest_server_version_for_lineage "${version}.0")

        support_source_config "${g_registry}" "${version}" ""

        for edition in "${c_editions[@]}"; do
            if support_config_filter "${edition}" "${g_filter_editions[@]}"; then
                continue
            fi

            support_source_config "${g_registry}" "${version}" "${edition}"

            for distro in "${c_distros[@]}"; do
                if support_config_filter "${distro}" "${g_filter_distros[@]}"; then
                    continue
                fi

                test_targets_str+="$(do_bake_test_target "${version}" \
                    "${distro}" "${edition}")"
                push_targets_str+="$(do_bake_push_target "${version}" \
                    "${distro}" "${edition}")"
                group_test_targets+="$(do_bake_test_group_targets "${distro}" \
                    "${edition}" "${version}")"
                group_push_targets+="\"$(get_target_name "${version}" \
                    "${distro}" "${edition}" "")\", "
            done
        done

        group_test_targets=${group_test_targets%", "}
        group_push_targets=${group_push_targets%", "}
        group_test_targets+=",\n    "
        group_push_targets+=",\n    "
    done

    group_test_targets=${group_test_targets%",\n    "}
    group_push_targets=${group_push_targets%",\n    "}

    local test_group_str
    test_group_str="$(do_bake_group "test" "${group_test_targets}")"
    local push_group_str
    push_group_str="$(do_bake_group "push" "${group_push_targets}")"

    mkdir -p "${g_target_dir}"

    local bake_file="${g_target_dir}/bake.hcl"
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

    {
        printf "%b\n%b" "${test_group_str}" "${test_targets_str}"
        printf "%b\n%b" "${push_group_str}" "${push_targets_str}"
    } >>"${bake_file}"
}

function build_images() {
    local target=

    if [ "${g_test_build}" = "true" ]; then
        target="test"
    elif [ "${g_push_build}" = "true" ]; then
        target="push"
    fi

    local params=

    if [ "${g_test_build}" = "true" ]; then
        params="--load"
    elif [ "${g_push_build}" = "true" ]; then
        params="--push"
    fi

    local bake_file="${g_target_dir}/bake.hcl"

    log_info "main() - build '${bake_file}'"

    local revision=
    revision="$(git rev-parse HEAD)"
    local created=
    created="$(date --utc --rfc-3339=seconds -d "@${g_start_time}")"

    verbose_call docker buildx bake --pull --progress plain ${params} \
        --set "\*.labels.org.opencontainers.image.revision=\"${revision}\"" \
        --set "\*.labels.org.opencontainers.image.created=\"${created}\"" \
        --file "${bake_file}" "${target}"
}

function main() {
    parse_args "$@"

    g_start_time="$(date --utc +%s)"

    build_bake_file

    if [ "${g_dry_run}" = "true" ]; then
        exit 0
    fi

    build_images
}

main "$@"
