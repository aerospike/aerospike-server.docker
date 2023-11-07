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
    local version_path=$1
    local edition=$2

    local version=
    version="$(basename "${version_path}")"
    local config_dir="${g_data_config_dir}/${version}"

    # shellcheck source=data/config/6.4/config.sh
    source "${config_dir}/config.sh"

    local edition_config="${config_dir}/config_${edition}.sh"

    if [ -f "${edition_config}" ]; then
        # shellcheck source=data/config/6.4/config_federal.sh
        source "${edition_config}"
    fi
}
