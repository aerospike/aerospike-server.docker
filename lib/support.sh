#!/usr/bin/env bash

set -Eeuo pipefail

source lib/log.sh
source lib/version.sh

function support_all_editions() {
    echo "enterprise federal community"
}

function support_editions_for_asd() {
    local version=$1

    if version_compare_gt "6.0" "${version}"; then
        echo "enterprise community"
        return
    fi

    echo "enterprise federal community"
}

function support_distro_to_base() {
    local distro=$1

    case "${distro}" in
    ubuntu20.04)
        echo "ubuntu:20.04"
        ;;
    ubuntu22.04)
        echo "ubuntu:22.04"
        ;;
    ubuntu24.04)
        echo "ubuntu:24.04"
        ;;
    *)
        warn "unsupported distro '${distro}'"
        exit 1
        ;;
    esac
}

function support_distros_for_asd() {
    local version=$1

    if version_compare_gt "6.3" "${version}"; then
        echo "ubuntu20.04"
        return
    fi

    if version_compare_gt "7.2" "${version}"; then
        echo "ubuntu22.04"
        return
    fi

    echo "ubuntu24.04"
}

function support_arch_for_asd() {
    local version=$1

    if version_compare_gt "6.2" "${version}"; then
        echo "x86_64"
        return
    fi

    echo "x86_64 aarch64"
}

function support_platforms_for_asd() {
    local version=$1
    local edition=$2

    if version_compare_gt "6.2" "${version}"; then
        echo "linux/amd64"
        return
    fi

    if [ "${edition}" = "federal" ]; then
        echo "linux/amd64"
    fi

    echo "linux/amd64 linux/arm64"
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
        warn "Unexpected platform '${platform}'"
        exit 1
        ;;
    esac
}
