#!/usr/bin/env bash
# Version utilities for Aerospike Docker images
#
# Supported version formats:
#   - 8.1.1.0                      (release)
#   - 8.1.1.0-rc2                  (release candidate)
#   - 8.1.1.0-start-16             (development build)
#   - 8.1.1.0-start-16-gea126d3    (development build with git hash)

set -Eeuo pipefail

source lib/fetch.sh

ARTIFACTS_DOMAIN=${ARTIFACTS_DOMAIN:="https://download.aerospike.com/artifacts"}

# Check if URL is a direct edition URL (contains aerospike-server-<edition>)
function is_direct_url() {
    [[ "${ARTIFACTS_DOMAIN}" =~ aerospike-server-(community|enterprise|federal) ]]
}

# Check if URL is a JFrog Artifactory repo (flat distro/arch layout: base/el9/x86_64/pkg.rpm)
function is_artifactory_repo() {
    [[ "${ARTIFACTS_DOMAIN}" =~ jfrog\.io|artifactory|/database-rpm-|/database-deb- ]]
}

# Find the latest version for a release lineage (e.g., 7.1 -> 7.1.0.20)
function find_latest_version_for_lineage() {
    local lineage=$1
    local url

    if is_direct_url; then
        url="${ARTIFACTS_DOMAIN}/"
    else
        url="${ARTIFACTS_DOMAIN}/aerospike-server-enterprise/"
    fi

    fetch "version" "${url}" 2>/dev/null |
        grep -oE "\"${lineage}\.[0-9]+\.[0-9]+(-[a-z0-9]+(-[0-9]+(-g[a-f0-9]+)?)?)?/?\"" |
        tr -d '"/' | sort -V | tail -1
}

# Find the tools version for a server version (same for all editions/distros)
function find_tools_version() {
    local version=$1
    local url

    if is_direct_url; then
        url="${ARTIFACTS_DOMAIN}/${version}/"
    else
        url="${ARTIFACTS_DOMAIN}/aerospike-server-enterprise/${version}/"
    fi

    local page
    page=$(fetch "tools" "${url}" 2>/dev/null)

    # Extract tools version from any available package
    echo "${page}" | grep -oE "_tools-[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+(-[0-9]+)?)?_" |
        head -1 | sed 's/_tools-//; s/_$//'
}

# Get the download link for a package (tgz bundle)
function get_package_link() {
    local artifact_distro=$1
    local edition=$2
    local version=$3
    local tools_version=$4
    local arch=$5

    # Federal doesn't support arm64
    if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
        echo ""
        return
    fi

    local base_url
    if is_direct_url; then
        base_url="${ARTIFACTS_DOMAIN}"
    else
        base_url="${ARTIFACTS_DOMAIN}/aerospike-server-${edition}"
    fi

    echo "${base_url}/${version}/aerospike-server-${edition}_${version}_tools-${tools_version}_${artifact_distro}_${arch}.tgz"
}

# Get server package link for native format (rpm or deb) - when tgz is not available
# Supports: version-based (default) and JFrog Artifactory layout (base/el9/x86_64/pkg.rpm)
function get_server_package_link_native() {
    local artifact_distro=$1
    local edition=$2
    local version=$3
    local tools_version=$4
    local arch=$5
    local pkg_type=$6

    if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
        echo ""
        return
    fi

    local base_url path_prefix
    if is_direct_url || is_artifactory_repo; then
        base_url="${ARTIFACTS_DOMAIN}"
    else
        base_url="${ARTIFACTS_DOMAIN}/aerospike-server-${edition}"
    fi

    if is_artifactory_repo; then
        # JFrog: database-rpm-prod-public-local/el9/x86_64/pkg.rpm (no version in path)
        path_prefix="${artifact_distro}/${arch}"
    else
        path_prefix="${version}"
    fi

    if [ "${pkg_type}" = "rpm" ]; then
        echo "${base_url}/${path_prefix}/aerospike-server-${edition}-${version}-1.${artifact_distro}.${arch}.rpm"
    else
        local deb_arch="${arch}"
        [ "${arch}" = "x86_64" ] && deb_arch="amd64"
        echo "${base_url}/${path_prefix}/aerospike-server-${edition}_${version}_${deb_arch}.deb"
    fi
}

# Get tools package link for native format (rpm or deb)
function get_tools_package_link_native() {
    local artifact_distro=$1
    local edition=$2
    local version=$3
    local tools_version=$4
    local arch=$5
    local pkg_type=$6

    if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
        echo ""
        return
    fi

    local base_url path_prefix
    if is_direct_url || is_artifactory_repo; then
        base_url="${ARTIFACTS_DOMAIN}"
    else
        base_url="${ARTIFACTS_DOMAIN}/aerospike-server-${edition}"
    fi

    if is_artifactory_repo; then
        path_prefix="${artifact_distro}/${arch}"
    else
        path_prefix="${version}"
    fi

    if [ "${pkg_type}" = "rpm" ]; then
        echo "${base_url}/${path_prefix}/aerospike-tools-${tools_version}-1.${artifact_distro}.${arch}.rpm"
    else
        local deb_arch="${arch}"
        [ "${arch}" = "x86_64" ] && deb_arch="amd64"
        echo "${base_url}/${path_prefix}/aerospike-tools_${tools_version}_${deb_arch}.deb"
    fi
}

# Fetch SHA256 for any package URL (link.sha256)
function fetch_sha_for_link() {
    local link=$1
    [ -z "${link}" ] && { echo ""; return; }
    fetch "sha" "${link}.sha256" 2>/dev/null | cut -f1 -d' '
}

# Fetch SHA256 checksum for a package (tgz)
function fetch_package_sha() {
    local link
    link="$(get_package_link "$@")"
    [ -z "${link}" ] && {
        echo ""
        return
    }
    fetch_sha_for_link "${link}"
}
