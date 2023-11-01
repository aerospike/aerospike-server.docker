source lib/log.sh
source lib/version.sh

function support_source_config() {
    version_path=$1
    edition=$2

    # shellcheck source=images/6.4/config.sh
    source "${version_path}/config.sh"

    local edition_config="${version_path}/config_${edition}.sh"

    if [ -f "${edition_config}" ]; then
        # shellcheck source=images/6.4/config_federal.sh
        source "${edition_config}"
    fi
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
