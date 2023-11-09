# shellcheck shell=bash

source lib/array.sh
source lib/globals.sh
source lib/log.sh
source lib/version.sh

function support_config_filter() {
    local needle=$1
    shift
    local array=("$@")

    ! array_empty "${array[@]}" && ! in_array "${needle}" "${array[@]}"
}

function support_platform_to_arch() {
    local platform=$1

    case "${platform}" in
    "linux/amd64")
        echo "x86_64"
        ;;
    "linux/arm64")
        echo "aarch64"
        ;;
    *)
        log_warn "Unexpected platform '${platform}'"
        exit 1
        ;;
    esac
}

function support_source_config() {
    local registry=$1
    local version=$2
    local edition=$3

    # Apply registry config.
    local registry_config_dir="${g_data_config_dir}/${registry}"
    local registry_config="${registry_config_dir}/config.sh"

    if [ -f "${registry_config}" ]; then
        # shellcheck source=data/config/dockerhub/config.sh
        source "${registry_config}"
    fi

    # Apply version config (required).
    local version_config_dir="${registry_config_dir}/${version}"

    # shellcheck source=data/config/dockerhub/6.4/config.sh
    source "${version_config_dir}/config.sh"

    if [ -z "${edition}" ]; then
        return
    fi

    # Apply edition config (required).
    local edition_config="${version_config_dir}/${edition}/config.sh"

    if [ -f "${edition_config}" ]; then
        # shellcheck source=data/config/dockerhub/6.4/federal/config.sh
        source "${edition_config}"
    fi
}

function _dir_dirs() {
    local search_dir=$1

    while IFS= read -r -d '' dir; do
        local found_dir=
        found_dir=$(basename "${dir}")
        echo "${found_dir}"
    done < <(find "${search_dir}" -mindepth 1 -maxdepth 1 -type d -print0)
}

function support_registries() {
    _dir_dirs "${g_data_config_dir}" | sort
}

function support_versions() {
    local registry=$1

    _dir_dirs "${g_data_config_dir}/${registry}" | sort
}

function support_editions() {
    local registry=$1
    local version=$2

    _dir_dirs "${g_data_config_dir}/${registry}/${version}" | sort
}

function support_configs() {
    local prev
    local leaf_config_path

    while IFS= read -r -d '' leaf_config_path; do
        if [[ ${prev} =~ ${leaf_config_path} ]]; then
            continue
        fi

        prev="${leaf_config_path}"
        echo "${leaf_config_path}"
    done < <(find "${g_data_config_dir}" -depth -type d -print0)
}
