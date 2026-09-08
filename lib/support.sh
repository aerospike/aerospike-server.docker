#!/usr/bin/env bash
# Support matrix and distro/edition helpers for Aerospike Docker images.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/log.sh. Canonical lineage order (linear): 7.1, 7.2, 8.0, 8.1, 8.2

set -Eeuo pipefail

source lib/log.sh

# Supported release lineages (order preserved for build/test iteration).
#
# A lineage joins this list only once its packages are published: an unresolvable
# lineage here is skipped with a warning by -g/-t, but -p refuses to push a
# partial matrix, so listing 8.2 early would break every all-lineage push. A
# targeted `-g 8.2` does not consult this list and works as soon as the packages
# land -- it needs only the support_distros entry below.
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
    8.1 | 8.2)
        echo "ubuntu24.04 ubi10"
        ;;
    # An unknown lineage used to fall back to 7.1's distros. This function is
    # also what generate.sh prunes with: a -g of that lineage rm -rf's every
    # distro directory the fallback does not name, so a lineage added to
    # releases/ but not here would have its real distros deleted and replaced
    # with ones its packages were never built for. There is no safe guess.
    *)
        log_warn "unsupported release lineage '${lineage}' - add it to support_distros"
        exit 1
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
    # shellcheck disable=SC2086
    for d in ${all_distros}; do
        # shellcheck disable=SC2086
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
    ubi9) echo "registry.access.redhat.com/ubi9/ubi-minimal:9.7" ;;
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

# Every artifact distro name this tool recognises, including ones no longer
# built for -- a package filename naming a retired distro must still be
# recognised as distro-specific rather than treated as portable. Used to tell a
# hand-named, distro-less package from one built for a different distro. Keep in
# step with the case above and with support_distro_to_apt_suite.
function support_artifact_distros() {
    echo "ubuntu20.04 ubuntu22.04 ubuntu24.04 el8 el9 el10"
}

# Map an artifact distro name to its Debian/Ubuntu apt suite (the codename used
# as the pool/ and dists/ path component in the JFrog apt repos). Empty for
# non-deb distros.
function support_distro_to_apt_suite() {
    case "$1" in
    ubuntu20.04) echo "focal" ;;
    ubuntu22.04) echo "jammy" ;;
    ubuntu24.04) echo "noble" ;;
    ubuntu26.04) echo "resolute" ;;
    debian11) echo "bullseye" ;;
    debian12) echo "bookworm" ;;
    debian13) echo "trixie" ;;
    *) echo "" ;;
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
    # shellcheck disable=SC2086
    for plat in ${all_platforms}; do
        local arch="${plat#*/}"
        # shellcheck disable=SC2086
        for f in ${filter_tokens}; do
            case "${f}" in
            amd64 | x86_64)
                [ "${arch}" = "amd64" ] && {
                    out="${out} ${plat}"
                    break
                }
                ;;
            arm64 | aarch64)
                [ "${arch}" = "arm64" ] && {
                    out="${out} ${plat}"
                    break
                }
                ;;
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
