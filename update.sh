#!/usr/bin/env bash

set -Eeuo pipefail

source lib/fetch.sh
source lib/globals.sh
source lib/log.sh
source lib/support.sh
source lib/version.sh

function bash_eval_template() {
    local template_file=$1
    local target_file=$2

    echo "" >"${target_file}"

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

    while IFS= read -r -d '' template_file; do
        target_file="${template_file%.template}"
        bash_eval_template "${template_file}" "${target_file}"
    done < <(find "${target_path}" -type f -name "*.template" -print0)
}

function copy_template() {
    local template_path="template"
    local target_path=$1

    if [ -d "${target_path}" ]; then
        log_warn "unexpected - found '${target_path}'"
    fi

    mkdir -p "${target_path}"

    for override in \
        $(find template/ -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort -V); do
        if ! version_compare_gt "${override}" "${g_server_version}"; then
            local override_path="${template_path}/${override}/"

            log_debug "copy_template - ${override_path} to ${target_path}"
            cp -r "${override_path}"/* "${target_path}"
        fi
    done
}

function do_template() {
    local version_path=$1
    local edition=$2
    local distro=$3
    local distro_base=$4

    log_info "do_template() - edition '${edition}' distro '${distro}' distro_base '${distro_base}'"

    # These are variables used by the template.
    DEBUG="${DEBUG:=false}"
    LINUX_BASE="${distro_base}"
    LINUX_PKG_TYPE=
    AEROSPIKE_VERSION="${g_server_version}"
    AEROSPIKE_EDITION="${edition}"
    AEROSPIKE_DESCRIPTION="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions."
    AEROSPIKE_X86_64_LINK=
    AEROSPIKE_SHA_X86_64=
    AEROSPIKE_AARCH64_LINK=
    AEROSPIKE_SHA_AARCH64=

    if grep -o "debian:" <<<"${distro_base}"; then
        LINUX_PKG_TYPE="deb"
    elif grep -o "redhat/" <<<"${distro_base}"; then
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
                    "${arch}")"
                AEROSPIKE_SHA_AARCH64="$(fetch_package_sha "${distro}" \
                    "${edition}" "${g_server_version}" "${g_tools_version}" \
                    "${arch}")"

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
                    "${arch}")"
                AEROSPIKE_SHA_X86_64="$(fetch_package_sha "${distro}" \
                    "${edition}" "${g_server_version}" "${g_tools_version}" \
                    "${arch}")"

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
    log_info "LINUX_BASE: '${LINUX_BASE}'"
    log_info "LINUX_PKG_TYPE: '${LINUX_PKG_TYPE}'"
    log_info "AEROSPIKE_VERSION: '${AEROSPIKE_VERSION}'"
    log_info "AEROSPIKE_EDITION: '${AEROSPIKE_EDITION}'"
    log_info "AEROSPIKE_DESCRIPTION: '${AEROSPIKE_DESCRIPTION}'"
    log_info "AEROSPIKE_X86_64_LINK: '${AEROSPIKE_X86_64_LINK}'"
    log_info "AEROSPIKE_SHA_X86_64: '${AEROSPIKE_SHA_X86_64}'"
    log_info "AEROSPIKE_AARCH64_LINK: '${AEROSPIKE_AARCH64_LINK}'"
    log_info "AEROSPIKE_SHA_AARCH64: '${AEROSPIKE_SHA_AARCH64}'"

    local target_path="${version_path}/${edition}/${distro}"

    copy_template "${target_path}"
    bash_eval_templates "${target_path}"
}

function update_version() {
    local version_path=$1

    local version=
    version="$(basename "${version_path}")"

    # HACK - artifacts for server need first 3 digits.
    g_server_version=$(find_latest_server_version_for_lineage "${version}.0")

    support_source_config "${version_path}" ""

    for distro in "${c_distros[@]}"; do
        # Assumes that there will always be an 'enterprise' edition.
        g_tools_version=$(find_latest_tools_version_for_server "${distro}" enterprise "${g_server_version}")
        break
    done

    log_info "update_version() - server '${version}' -> '${g_server_version}' tools '${g_tools_version}'"

    # Clear prior builds.
    for edition in "${g_all_editions[@]}"; do
        local path="${version_path}/${edition}"

        if [ -d "${path}" ]; then
            find "${version_path}/${edition}" -mindepth 1 -maxdepth 1 -type d \
                 -exec rm -rf {} \;
        fi
    done

    # Generate new builds.
    for edition in "${c_editions[@]}"; do
        support_source_config "${version_path}" "${edition}"

        for distro_ix in "${!c_distros[@]}"; do
            local distro="${c_distros[${distro_ix}]}"
            local distro_base="${c_distro_bases[${distro_ix}]}"

            do_template "${version_path}" "${edition}" "${distro}" "${distro_base}"
        done
    done
}

function main() {
    for version_path in "${g_images_dir}"/*; do
        update_version "${version_path}"
    done
}

main "$@"
