#!/usr/bin/env bash

set -Eeuo pipefail

source lib/fetch.sh
source lib/globals.sh
source lib/log.sh
source lib/support.sh
source lib/version.sh

function usage() {
    cat <<EOF
Usage: $0 [-s] [-h|--help]

    -h display this help.

    -y <registry name> as it apprears in '${g_data_config_dir}. May be repeated.
    -d <distro name> as it appears in 'config.sh'. May be repeated.
    -e <Aerospike edition> as it appears in 'config.sh'. May be repeated.
    -s <full server version>.
EOF
}

function parse_args() {
    g_filter_registries=()
    g_filter_full_versions=()
    g_filter_short_versions=()
    g_filter_editions=()
    g_filter_distros=()

    g_has_filters="false"

    while getopts "d:e:hs:y:" opt; do
        case "${opt}" in
        d)
            g_filter_distros+=("${OPTARG}")
            g_has_filters="true"
            ;;
        e)
            g_filter_editions+=("${OPTARG}")
            g_has_filters="true"
            ;;
        h)
            usage
            exit 0
            ;;
        s)
            g_filter_full_versions+=("${OPTARG}")
            g_has_filters="true"
            ;;
        y)
            g_filter_registries+=("${OPTARG}")
            g_has_filters="true"
            ;;

        *)
            log_warn "** Invalid argument **"
            usage
            exit 1
            ;;
        esac
    done

    local temp
    temp="$(printf "'%s' " "${g_filter_registries[@]}")"
    log_info "g_filter_registries: (${temp%" "})"
    temp="$(printf "'%s' " "${g_filter_full_versions[@]}")"
    log_info "g_filter_full_versions: (${temp%" "})"
    temp="$(printf "'%s' " "${g_filter_editions[@]}")"
    log_info "g_filter_editions: (${temp%" "})"
    temp="$(printf "'%s' " "${g_filter_distros[@]}")"
    log_info "g_filter_distros: (${temp%" "})"

    for full_ver in "${g_filter_full_versions[@]}"; do
        short_ver=$(sed -E 's/(\.[0-9]+){2}(-rc.*)?$//' <<<"${full_ver}")
        g_filter_short_versions+=("${short_ver}")
    done

    temp="$(printf "'%s' " "${g_filter_short_versions[@]}")"
    log_info "g_filter_short_versions: (${temp%" "})"
}

function create_meta() {
    local target_path=$1

    target_file="${target_path}/meta"

    {
        echo "META_DEBUG='${DEBUG}'"
        echo "META_DOCKER_REGISTRY_URL='${DOCKER_REGISTRY_URL}'"
        echo "META_LINUX_BASE='${LINUX_BASE}'"
        echo "META_LINUX_PKG_TYPE='${LINUX_PKG_TYPE}'"
        echo "META_AEROSPIKE_VERSION='${AEROSPIKE_VERSION}'"
        echo "META_AEROSPIKE_EDITION='${AEROSPIKE_EDITION}'"
        echo "META_AEROSPIKE_DESCRIPTION='${AEROSPIKE_DESCRIPTION}'"
        echo "META_AEROSPIKE_X86_64_LINK='${AEROSPIKE_X86_64_LINK}'"
        echo "META_AEROSPIKE_SHA_X86_64='${AEROSPIKE_SHA_X86_64}'"
        echo "META_AEROSPIKE_AARCH64_LINK='${AEROSPIKE_AARCH64_LINK}'"
        echo "META_AEROSPIKE_SHA_AARCH64='${AEROSPIKE_SHA_AARCH64}'"
    } > "${target_file}"
}

function bash_eval_template() {
    local template_file=$1
    local target_file=$2

    echo "" >"${target_file}"

    while IFS= read -r line; do
        if grep -qE "[$][(]|[{]" <<<"${line}"; then
            local update
            update=$(eval echo "\"${line}\"") || exit 1
            grep -qE "[^[:space:]]*" <<<"${update}" &&
                echo "${update}" >>"${target_file}"
        else
            echo "${line}" >>"${target_file}"
        fi
    done <"${template_file}"

    # Ignore failure when template is mounted in a read-only filesystem.
    rm "${template_file}" || true
}

function bash_eval_templates() {
    local target_path=$1

    while IFS= read -r -d '' template_file; do
        target_file="${template_file%.template}"
        bash_eval_template "${template_file}" "${target_file}"
    done < <(find "${target_path}" -type f -name "*.template" -print0)
}

function copy_template() {
    local target_path=$1

    if [ -d "${target_path}" ]; then
        log_warn "unexpected - found '${target_path}'"
    fi

    mkdir -p "${target_path}"

    for override in $(template_overrides); do
        if ! version_compare_gt "${override}" "${g_server_version}"; then
            local override_path="${g_data_template_dir}/${override}/"

            log_debug "copy_template - ${override_path} to ${target_path}"
            cp -r "${override_path}"/* "${target_path}"
        fi
    done
}

function do_template() {
    local registry=$1
    local version=$2
    local edition=$3
    local distro=$4
    local distro_dir=$5
    local distro_base=$6

    log_info "do_template() - edition '${edition}' distro '${distro}' distro_base '${distro_base}'"

    # These are variables used by the template.
    DEBUG="${DEBUG:=false}"
    DOCKER_REGISTRY_URL="${c_registry_url}"
    LINUX_BASE="${distro_base}"
    LINUX_PKG_TYPE=
    AEROSPIKE_VERSION="${g_server_version}"
    AEROSPIKE_EDITION="${edition}"
    AEROSPIKE_DESCRIPTION="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions."
    AEROSPIKE_X86_64_LINK=
    AEROSPIKE_SHA_X86_64=
    AEROSPIKE_AARCH64_LINK=
    AEROSPIKE_SHA_AARCH64=

    if grep -qo "debian:" <<<"${distro_base}"; then
        LINUX_PKG_TYPE="deb"
    elif grep -qEo "ubi[89]-" <<<"${distro_base}"; then
        LINUX_PKG_TYPE="rpm"
    else
        log_warn "unexpected distro_base '${distro_base}'"
        exit 1
    fi

    for arch in "${c_archs[@]}"; do
        case ${arch} in
        aarch64)
            AEROSPIKE_AARCH64_LINK="$(get_package_link "${distro}" \
                "${edition}" "${g_server_version}" "${g_tools_version}" \
                aarch64)"
            AEROSPIKE_SHA_AARCH64="$(fetch_package_sha "${distro}" \
                "${edition}" "${g_server_version}" "${g_tools_version}" \
                aarch64)"

            if [ -z "${AEROSPIKE_AARCH64_LINK}" ]; then
                log_warn "could not find aarch64 link"
                exit 1
            fi

            if [ -z "${AEROSPIKE_SHA_AARCH64}" ]; then
                log_warn "could not find aarch64 sha"
                exit 1
            fi
            ;;
        x86_64)
            AEROSPIKE_X86_64_LINK="$(get_package_link "${distro}" \
                "${edition}" "${g_server_version}" "${g_tools_version}" \
                x86_64)"
            AEROSPIKE_SHA_X86_64="$(fetch_package_sha "${distro}" \
                "${edition}" "${g_server_version}" "${g_tools_version}" \
                x86_64)"

            if [ -z "${AEROSPIKE_X86_64_LINK}" ]; then
                log_warn "could not find x86_64 link"
                exit 1
            fi

            if [ -z "${AEROSPIKE_SHA_X86_64}" ]; then
                log_warn "could not find x86_64 sha"
                exit 1
            fi
            ;;
        *)
            log_warn "unexpected arch '${arch}'"
            exit 1
            ;;
        esac
    done

    log_info "DEBUG: '${DEBUG}'"
    log_info "DOCKER_REGISTRY_URL: '${DOCKER_REGISTRY_URL}'"
    log_info "LINUX_BASE: '${LINUX_BASE}'"
    log_info "LINUX_PKG_TYPE: '${LINUX_PKG_TYPE}'"
    log_info "AEROSPIKE_VERSION: '${AEROSPIKE_VERSION}'"
    log_info "AEROSPIKE_EDITION: '${AEROSPIKE_EDITION}'"
    log_info "AEROSPIKE_DESCRIPTION: '${AEROSPIKE_DESCRIPTION}'"
    log_info "AEROSPIKE_X86_64_LINK: '${AEROSPIKE_X86_64_LINK}'"
    log_info "AEROSPIKE_SHA_X86_64: '${AEROSPIKE_SHA_X86_64}'"
    log_info "AEROSPIKE_AARCH64_LINK: '${AEROSPIKE_AARCH64_LINK}'"
    log_info "AEROSPIKE_SHA_AARCH64: '${AEROSPIKE_SHA_AARCH64}'"

    local target_path=
    target_path="$(support_image_path "${registry}" "${version}" "${edition}" \
        "${distro_dir}")"

    copy_template "${target_path}"
    create_meta "${target_path}"
    bash_eval_templates "${target_path}"
    cp "${g_license["${edition}"]}" "${target_path}"/LICENSE
}

function update_version() {
    local registry=$1
    local version=$2

    g_server_version=$(grep "^${version}"<<<"$(
        printf '%s\n' "${g_filter_full_versions[@]}")" || true)

    if [ -z "${g_server_version}" ]; then
        # HACK - artifacts for server need first 3 digits.
        g_server_version=$(find_latest_server_version_for_lineage "${version}.0")
    fi

    g_tools_version=

    support_source_config "${registry}" "${version}"

    for distro in "${c_distros[@]}"; do
        # Assumes that there will always be an 'enterprise' edition.
        g_tools_version=$(find_latest_tools_version_for_server \
            "${distro}" enterprise "${g_server_version}")
        break
    done

    log_info "update_version() - registry '${registry}' server '${version}' -> '${g_server_version}' tools '${g_tools_version}'"

    # Generate new builds.
    for edition in "${c_editions[@]}"; do
        if support_config_filter "${edition}" "${g_filter_editions[@]}"; then
            continue
        fi

        support_source_config "${registry}" "${version}" "${edition}"

        for distro_ix in "${!c_distros[@]}"; do
            local distro="${c_distros[${distro_ix}]}"
            local distro_dir="${c_distro_dir[${distro_ix}]}"
            local distro_base="${c_distro_bases[${distro_ix}]}"

            if support_config_filter "${distro}" "${g_filter_distros[@]}"; then
                continue
            fi

            do_template "${registry}" "${version}" "${edition}" "${distro}" \
                "${distro_dir}" "${distro_base}"
        done
    done
}

function main() {
    parse_args "$@"

    rm -rf "${g_images_dir:?}/"*

    for registry in $(support_registries); do
        if support_config_filter "${registry}" "${g_filter_registries[@]}"; then
            continue
        fi

        for version in $(support_versions "${registry}"); do
            if support_config_filter \
                   "${version}" "${g_filter_short_versions[@]}"; then
                continue
            fi

            update_version "${registry}" "${version}"
        done
    done

    if [[ "${g_has_filters}" == "true" ]]; then
        log_warn "Reminder - do not commit changes when updating with filters."
    fi
}

main "$@"
