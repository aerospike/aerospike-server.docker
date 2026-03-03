#!/usr/bin/env bash
# Support matrix and distro/edition helpers for Aerospike Docker images.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/log.sh. Canonical lineage order (linear): 7.1, 7.2, 8.0, 8.1

set -Eeuo pipefail

source lib/log.sh

# Supported release lineages (order preserved for build/test iteration)
RELEASES="7.1 7.2 8.0 8.1"

# Supported editions
EDITIONS="community enterprise federal"

function support_releases() {
    echo "${RELEASES}"
}

function support_editions() {
    echo "${EDITIONS}"
}

# Get supported distros for a release lineage (single source of truth per lineage).
function support_distros() {
    local lineage=${1:-}

    case "${lineage}" in
    7.1)
        echo "ubuntu22.04 ubi9"
        ;;
    7.2 | 8.0)
        echo "ubuntu24.04 ubi9"
        ;;
    8.1 | *)
        echo "ubuntu24.04 ubi9"
        ;;
    esac
}

# Return distros for lineage that match any filter (exact or prefix). No filter = all.
# Usage: support_distros_matching lineage ""  or  support_distros_matching lineage "ubuntu ubi9"
function support_distros_matching() {
    local lineage=$1
    local filter_tokens=$2
    local all_distros
    all_distros=$(support_distros "${lineage}")
    if [ -z "${filter_tokens}" ]; then
        echo "${all_distros}"
        return
    fi
    local out=""
    for d in ${all_distros}; do
        for f in ${filter_tokens}; do
            if [ "${d}" = "${f}" ] || [[ "${d}" == "${f}"* ]]; then
                out="${out} ${d}"
                break
            fi
        done
    done
    echo "${out# }"
}

function support_distro_to_base() {
    case "$1" in
    ubuntu22.04) echo "ubuntu:22.04" ;;
    ubuntu24.04) echo "ubuntu:24.04" ;;
    ubi9) echo "registry.access.redhat.com/ubi9/ubi-minimal:9.4" ;;
    ubi10) echo "registry.access.redhat.com/ubi10/ubi-minimal:10.0" ;;
    *)
        log_warn "unsupported distro '$1'"
        exit 1
        ;;
    esac
}

# Package type by OS: rpm for UBI/RHEL (ubi9, ubi10), deb for Ubuntu
function support_distro_to_pkg_type() {
    case "$1" in
    ubuntu*) echo "deb" ;;
    ubi*) echo "rpm" ;;
    *)
        log_warn "unsupported distro '$1'"
        exit 1
        ;;
    esac
}

function support_distro_to_artifact_name() {
    case "$1" in
    ubuntu22.04) echo "ubuntu22.04" ;;
    ubuntu24.04) echo "ubuntu24.04" ;;
    ubi9) echo "el9" ;;
    ubi10) echo "el10" ;;
    *)
        log_warn "unsupported distro '$1'"
        exit 1
        ;;
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

# Filter platforms by arch filter(s). arch_filter can be amd64, x86_64, arm64, aarch64 (multiple allowed).
# Empty filter = all platforms for edition. Returns space-separated linux/amd64, linux/arm64.
function support_platforms_matching() {
    local edition=$1
    local filter_tokens=$2
    local all_platforms
    all_platforms=$(support_platforms "${edition}")
    if [ -z "${filter_tokens}" ]; then
        echo "${all_platforms}"
        return
    fi
    local out=""
    for plat in ${all_platforms}; do
        local arch="${plat#*/}"
        for f in ${filter_tokens}; do
            case "${f}" in
            amd64 | x86_64) [ "${arch}" = "amd64" ] && { out="${out} ${plat}"; break; } ;;
            arm64 | aarch64) [ "${arch}" = "arm64" ] && { out="${out} ${plat}"; break; } ;;
            esac
        done
    done
    echo "${out# }"
}

function support_platform_to_arch() {
    case "$1" in
    "linux/amd64") echo "x86_64" ;;
    "linux/arm64") echo "aarch64" ;;
    *)
        log_warn "unexpected platform '$1'"
        exit 1
        ;;
    esac
}
