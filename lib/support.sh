#!/usr/bin/env bash
# Support functions for Aerospike Docker images
# Supports: 7.1+

set -Eeuo pipefail

source lib/log.sh

# Supported releases
RELEASES="7.1 7.2 8.0 8.1"

# Supported editions
EDITIONS="community enterprise federal"

function support_releases() {
    echo "${RELEASES}"
}

function support_editions() {
    echo "${EDITIONS}"
}

# Get supported distros for a release lineage
function support_distros() {
    local lineage=${1:-}

    case "${lineage}" in
        7.1)
            # 7.1 uses ubuntu22.04 (no ubuntu24.04 packages available)
            echo "ubuntu22.04 ubi9"
            ;;
        7.2|8.0)
            # 7.2 and 8.0 use ubuntu24.04, ubi9
            echo "ubuntu24.04 ubi9"
            ;;
        8.1|*)
            # 8.1+ adds ubi10 support
            echo "ubuntu24.04 ubi9 ubi10"
            ;;
    esac
}

function support_distro_to_base() {
    case "$1" in
        ubuntu22.04) echo "ubuntu:22.04" ;;
        ubuntu24.04) echo "ubuntu:24.04" ;;
        ubi9)        echo "registry.access.redhat.com/ubi9/ubi-minimal:9.4" ;;
        ubi10)       echo "registry.access.redhat.com/ubi10/ubi-minimal:10.0" ;;
        *)           log_warn "unsupported distro '$1'"; exit 1 ;;
    esac
}

function support_distro_to_pkg_type() {
    case "$1" in
        ubuntu*) echo "deb" ;;
        ubi*)    echo "rpm" ;;
        *)       log_warn "unsupported distro '$1'"; exit 1 ;;
    esac
}

function support_distro_to_artifact_name() {
    case "$1" in
        ubuntu22.04) echo "ubuntu22.04" ;;
        ubuntu24.04) echo "ubuntu24.04" ;;
        ubi9)        echo "el9" ;;
        ubi10)       echo "el10" ;;
        *)           log_warn "unsupported distro '$1'"; exit 1 ;;
    esac
}

function support_platforms() {
    local edition=${1:-}
    # Federal only supports amd64
    if [ "${edition}" = "federal" ]; then
        echo "linux/amd64"
    else
        echo "linux/amd64 linux/arm64"
    fi
}

function support_platform_to_arch() {
    case "$1" in
        "linux/amd64") echo "x86_64" ;;
        "linux/arm64") echo "aarch64" ;;
        *)             log_warn "unexpected platform '$1'"; exit 1 ;;
    esac
}
