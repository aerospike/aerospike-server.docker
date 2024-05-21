#!/usr/bin/env bash

set -Eeuo pipefail

source lib/fetch.sh
source lib/log.sh
source lib/support.sh
source lib/version.sh

function copy_template() {
    local template_path="template"
    local target_path=$1

    if [ -d "${target_path}" ]; then
        log_warn "unexpected - found '${target_path}'"
    fi

    mkdir -p "${target_path}"

    local override
    for override in \
        $(find template/* -maxdepth 1 -type d -printf "%f\n" | sort -V); do
        if ! version_compare_gt "${override}" "${g_server_version}"; then
            local override_path="${template_path}/${override}/"

            log_debug "copy_template - ${override_path} to ${target_path}"
            cp -r "${override_path}"/* "${target_path}"
        fi
    done
}

function bash_eval_template() {
    local template_file=$1
    local target_file=$2

    echo "" >"${target_file}"

    local line
    while IFS= read -r line; do
        if grep -qE "[$][(]|[{]" <<<"${line}"; then
            local update
            update=$(eval echo "\"${line}\"") || exit 1
            grep -qE "[^[:space:]]*" <<<"${update}" && echo "${update}" >>"${target_file}"
        else
            echo "${line}" >>"${target_file}"
        fi
    done <"${template_file}"

    # Ignore failure when template is mounted in a read-only filesystem.
    rm "${template_file}" || true
}

function bash_eval_templates() {
    local target_path=$1

    local template_file
    while IFS= read -r -d '' template_file; do
        target_file="${template_file%.template}"
        bash_eval_template "${template_file}" "${target_file}"
    done < <(find "${target_path}" -type f -name "*.template" -print0)
}

function do_template() {
    local distro=$1
    local edition=$2

    log_info "do_template() - distro '${distro}' edition '${edition}'"

    if [ -z "${g_tools_version}" ]; then
        # Use the first lookup, the version should be the same for each.
        g_tools_version=$(find_latest_tools_version_for_server "${distro}" "${edition}" "${g_server_version}")
    fi

    # These are variables used by the template.
    DEBUG="${DEBUG:=false}"
    LINUX_BASE="$(support_distro_to_base "${distro}")"
    AEROSPIKE_VERSION="${g_server_version}"
    CONTAINER_RELEASE="${g_container_release}"
    AEROSPIKE_EDITION="${edition}"
    AEROSPIKE_DESCRIPTION="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions."
    AEROSPIKE_X86_64_LINK="$(get_package_link "${distro}" "${edition}" "${g_server_version}" "${g_tools_version}" "x86_64")"
    AEROSPIKE_SHA_X86_64="$(fetch_package_sha "${distro}" "${edition}" "${g_server_version}" "${g_tools_version}" "x86_64")"
    AEROSPIKE_AARCH64_LINK="$(get_package_link "${distro}" "${edition}" "${g_server_version}" "${g_tools_version}" "aarch64")"
    AEROSPIKE_SHA_AARCH64="$(fetch_package_sha "${distro}" "${edition}" "${g_server_version}" "${g_tools_version}" "aarch64")"

    log_info "DEBUG: '${DEBUG}'"
    log_info "LINUX_BASE: '${LINUX_BASE}'"
    log_info "AEROSPIKE_VERSION: '${AEROSPIKE_VERSION}'"
    log_info "CONTAINER_RELEASE: '${CONTAINER_RELEASE}'"
    log_info "AEROSPIKE_EDITION: '${AEROSPIKE_EDITION}'"
    log_info "AEROSPIKE_DESCRIPTION: '${AEROSPIKE_DESCRIPTION}'"
    log_info "AEROSPIKE_X86_64_LINK: '${AEROSPIKE_X86_64_LINK}'"
    log_info "AEROSPIKE_SHA_X86_64: '${AEROSPIKE_SHA_X86_64}'"
    log_info "AEROSPIKE_AARCH64_LINK: '${AEROSPIKE_AARCH64_LINK}'"
    log_info "AEROSPIKE_SHA_AARCH64: '${AEROSPIKE_SHA_AARCH64}'"

    local target_path="${edition}/${distro}"

    copy_template "${target_path}"
    bash_eval_templates "${target_path}"
}

function usage() {
    cat <<EOF
Usage: $0 e|h|r -r <container release> -s <server version> -t <tools version>

    -e Edition to update
    -g Collects version information form 'git describe --abbrev=0'
    -h Display this help.
    -r <container release> Use if re-releasing an image - should increment by
        one for each re-release.
    -s <server version> Use this version instead of scraping the latest version
        from artifacts.
    -t <tools version> Use this version instead of scraping the latest version
        for a particular server version from artifacts.
EOF
}

function parse_args() {
    g_server_edition=
    g_server_version=
    g_server_maj_min_version=
    g_container_release='1'
    g_tools_version=

    while getopts "e:ghr:s:t:" opt; do
        case "${opt}" in
        e)
            g_server_edition="${OPTARG}"
            ;;
        g)
            local git_describe
            git_describe="$(git describe --abbrev=0)"

            if grep -q "_" <<<"${git_describe}"; then
                g_server_version="$(cut -sd _ -f 1 <<<"${git_describe}")"
                g_container_release="$(cut -sd _ -f 2 <<<"${git_describe}")"
            else
                g_server_version="${git_describe}"
                g_container_release='1'
            fi
            ;;
        h)
            usage
            exit 0
            ;;
        r)
            g_container_release="${OPTARG}"
            ;;
        s)
            g_server_version="${OPTARG}"
            ;;
        t)
            g_tools_version="${OPTARG}"
            ;;
        *)
            log_warn "** Invalid argument **"
            usage
            exit 1
            ;;
        esac
    done

    shift $((OPTIND - 1))
    
    g_server_maj_min_version="$(cut -sd . -f 1-2 <<<"${g_server_version}")"
}

function generate_templates() {
    local all_editions
    IFS=' ' read -r -a all_editions <<<"$(support_all_editions)"

    # Clear prior builds.
    local edition
    for edition in "${all_editions[@]}"; do
        find "${edition}"/* -maxdepth 0 -type d -exec rm -rf {} \;
    done

    # Generate new builds.
    local edition
    for edition in "${g_editions[@]}"; do
        local distro
        for distro in "${g_distros[@]}"; do
            do_template "${distro}" "${edition}"
        done
    done
}

function do_bake_test_group_targets() {
    local distro="${1//\./-}"
    local edition=$2

    local platform_list
    IFS=' ' read -r -a platform_list <<<"$(support_platforms_for_asd "${g_server_version}" "${edition}")"

    local output=""

    local platform
    for platform in "${platform_list[@]}"; do
        local short_platform=${platform#*/}
        local target_str="${edition}_${distro}_${short_platform}"

        output+="\"${target_str}\", "
    done

    printf "%s" "${output}"
}

function do_bake_group() {
    local group=$1

    local output="#------------------------------------ ${group} -----------------------------------\n\n"

    output+="group \"${group}\" {\n    targets=["

    local edition
    for edition in "${g_editions[@]}"; do
        local distro
        for distro in "${g_distros[@]}"; do
            distro="${distro//\./-}"
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

    printf "%s" "${output}"
}

function do_bake_test_target() {
    local distro=$1
    local edition=$2

    local distroTmp
    local platform_list
    local output=""

    distroTmp="${distro//\./-}"
    IFS=' ' read -r -a platform_list <<<"$(support_platforms_for_asd "${g_server_version}" "${edition}")"

    local platform
    for platform in "${platform_list[@]}"; do
        local short_platform=${platform#*/}
        local target_str="${edition}_${distroTmp}_${short_platform}"

        output+="target \"${target_str}\" {\n"
        output+="    tags=[\"aerospike/aerospike-server-${edition}-${short_platform}:${g_server_version}\", \"aerospike/aerospike-server-${edition}-${short_platform}:latest\"]\n"
        output+="    platforms=[\"${platform}\"]\n"
        output+="    context=\"./${edition}/${distro}\"\n"
        output+="}\n\n"
    done

    printf "%s" "${output}"
}

function do_bake_push_target() {
    local distro=$1
    local edition=$2
    local distroTmp
    local platform_list

    distroTmp="${distro//\./-}"
    IFS=' ' read -r -a platform_list <<<"$(support_platforms_for_asd "${g_server_version}" "${edition}")"

    printf -v platforms_str '%s,' "${platform_list[@]}"
    platforms_str="${platforms_str%,}"

    local target_str="${edition}_${distroTmp}"
    local output="target \"${target_str}\" {\n"

    local product="aerospike/aerospike-server"

    if [ "${edition}" != "community" ]; then
        product+="-${edition}"
    fi

    output+="    tags=[\"${product}:${g_server_version}\""
    output+=", \"${product}:${g_server_maj_min_version}\""
    
    if [ -n "${g_container_release}" ]; then
        output+=", \"${product}:${g_server_version}_${g_container_release}\""
    fi

    if [ "${g_latest_version}" = "${g_server_version}" ]; then
        output+=", \"${product}:latest\""
    fi

    output+="]\n"
    output+="    platforms=[\"${platforms_str}\"]\n"
    output+="    context=\"./${edition}/${distro}\"\n"
    output+="}\n\n"

    printf "%s" "${output}"
}

function generate_bake_file() {
    local bake_file="bake.hcl"

    cat <<-EOF >"${bake_file}"
# This file contains the targets for the test images.
# This file is auto-generated by the update.sh script and will be wiped out by the update.sh script.
# Please don't edit this file.
#
# Build all test/push images:
#      docker buildx bake -f ${bake_file} [test | push] --progressive plain [--load | --push]
# Build selected images:
#      docker buildx bake -f ${bake_file} [target name, ...] --progressive plain [--load | --push]

EOF

    local test_targets_str=""
    local push_targets_str=""

    local edition
    for edition in "${g_editions[@]}"; do
        local distro
        for distro in "${g_distros[@]}"; do
            test_targets_str+="$(do_bake_test_target "${distro}" "${edition}")"
            push_targets_str+="$(do_bake_push_target "${distro}" "${edition}")"
        done
    done

    local test_group_str
    test_group_str="$(do_bake_group "test")"
    local push_group_str
    push_group_str="$(do_bake_group "push")"

    {
        printf "%b\n%b" "${test_group_str}" "${test_targets_str}"
        printf "%b\n%b" "${push_group_str}" "${push_targets_str}"
    } >>"${bake_file}"
}

function main() {
    parse_args "$@"

    g_latest_version=

    if [ -z "${g_server_version}" ]; then
        g_server_version=$(find_latest_server_version)
        g_latest_version=g_server_version
    else
        g_server_version=$(find_latest_server_version_for_lineage "${g_server_version}")
        g_latest_version=$(find_latest_server_version)
    fi

    g_distros=
    IFS=' ' read -r -a g_distros <<<"$(support_distros_for_asd "${g_server_version}")"

    g_editions=

    if [ -z "${g_server_edition}" ]; then
        IFS=' ' read -r -a g_editions <<<"$(support_editions_for_asd "${g_server_version}")"
    else
        g_editions=("${g_server_edition}")
    fi

    generate_templates
    generate_bake_file
}

main "$@"
