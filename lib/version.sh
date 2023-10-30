#!/usr/bin/env bash

set -Eeuo pipefail

source lib/fetch.sh

ARTIFACTS_DOMAIN=${ARTIFACTS_DOMAIN:="https://artifacts.aerospike.com"}
RE_VERSION='[0-9]+[.][0-9]+[.][0-9]+([.][0-9]+)+(-rc[0-9]+)*'

function version_compare_gt() {
    v1=$1
    v2=$2

    if [ "$(printf "%s\n%s" "${v1}" "${v2}" | sort -V | head -1)" != "${v1}" ]; then
        return 0
    fi

    return 1
}

function find_latest_server_version() {
    local server_version

    # Note - we assume every release will have a enterprise component.
    server_version="$(
        fetch "${FUNCNAME[0]}" "${ARTIFACTS_DOMAIN}/aerospike-server-enterprise/" |
            grep -oE "${RE_VERSION}" |
            sort -V |
            tail -1
    )"

    echo "${server_version}"
}

function find_latest_server_version_for_lineage() {
    local lineage=$1

    local server_version

    # Note - we assume every release will have a enterprise component.
    server_version="$(
        fetch "${FUNCNAME[0]}" "${ARTIFACTS_DOMAIN}/aerospike-server-enterprise/${lineage}/" |
            grep -oE "${RE_VERSION}" |
            sort -V |
            head -1
    )"

    echo "${server_version}"
}

function find_latest_tools_version_for_server() {
    local distro=$1
    local edition=$2
    local server_version=$3

    if version_compare_gt "6.2" "${server_version}"; then
        # Tools version not part of package name prior to 6.2.
        log_debug "prior to 6.2"
        echo ""
        return
    fi

    log_debug "newer than 6.2"

    local tools_version
    tools_version="$(
        fetch "${FUNCNAME[0]}" "${ARTIFACTS_DOMAIN}/aerospike-server-${edition}/${server_version}/" |
            grep -oE "_tools-[0-9.-]+(-g[a-f0-9]{7})?_${distro}_x86_64.tgz" |
            cut -d _ -f 2 |
            sort -V |
            tail -1
    )"

    echo "${tools_version#tools-}"
}

function get_package_link() {
    local distro=$1
    local edition=$2
    local server_version=$3
    local tools_version=$4
    local arch=$5

    local link=

    if version_compare_gt "6.2" "${server_version}"; then
        if [ "${arch}" = "aarch64" ]; then
            # Did not support aarch64 prior to 6.2.
            echo ""
            return
        fi

        # Package names prior to 6.2.
        link="${ARTIFACTS_DOMAIN}/aerospike-server-${edition}/${server_version}/aerospike-server-${edition}-${server_version}-${distro}.tgz"
    else
        if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
            # Federal does not yet support arm.
            echo ""
            return
        fi

        # Package names 6.2 and later.
        link="${ARTIFACTS_DOMAIN}/aerospike-server-${edition}/${server_version}/aerospike-server-${edition}_${server_version}_tools-${tools_version}_${distro}_${arch}.tgz"
    fi

    echo "${link}"
}

function fetch_package_sha() {
    local distro=$1
    local edition=$2
    local server_version=$3
    local tools_version=$4
    local arch=$5

    local link=
    link="$(get_package_link "${distro}" "${edition}" "${server_version}" "${tools_version}" "${arch}")"

    if [ -z "${link}" ]; then
        echo ""
        return
    fi

    link="${link}.sha256"

    fetch "${FUNCNAME[0]}" "${link}" | cut -f 1 -d ' '
}

function get_version_from_dockerfile() {
    local distro=$1
    local edition=$2

    grep "ARG AEROSPIKE_X86_64_LINK=" "${edition}/${distro}/Dockerfile" | grep -oE "/[0-9.]+(-rc[0-9]+)?/" | tr -d '/'
}
