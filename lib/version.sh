#!/usr/bin/env bash
# Version utilities for Aerospike Docker images.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/fetch.sh (callers must also source lib/log.sh if using fetch with DEBUG).
#
# Supported version formats:
#   - 8.1.1.0                      (release)
#   - 8.1.1.0-rc2                  (release candidate)
#   - 8.1.1.0-start-16             (development build)
#   - 8.1.1.0-start-16-gea126d3    (development build with git hash)

set -Eeuo pipefail

source lib/fetch.sh

ARTIFACTS_DOMAIN=${ARTIFACTS_DOMAIN:="https://download.aerospike.com/artifacts"}

# Extract lineage (major.minor) from a full version string (e.g. 8.1.1.0 -> 8.1).
function get_lineage_from_version() {
    echo "$1" | grep -oE '^[0-9]+\.[0-9]+'
}

# Check if URL is a direct edition URL (contains aerospike-server-<edition>)
function is_direct_url() {
    [[ "${ARTIFACTS_DOMAIN}" =~ aerospike-server-(community|enterprise|federal) ]]
}

# Check if URL is a JFrog Artifactory repo (flat distro/arch layout: base/el9/x86_64/pkg.rpm)
function is_artifactory_repo() {
    [[ "${ARTIFACTS_DOMAIN}" =~ jfrog\.io|artifactory|/database-rpm-|/database-deb- ]]
}

# Check if -u points to a local directory (not http/https)
function is_local_artifacts_dir() {
    [[ "${ARTIFACTS_DOMAIN}" != http* ]]
}

# Find local server package file; echo path if found, else empty. Search base and base/version.
# Tries exact filename first, then glob match (e.g. *server*edition*arch*.rpm).
function find_local_server_package() {
    local base_dir=$1
    local artifact_distro=$2
    local edition=$3
    local version=$4
    local arch=$5
    local pkg_type=$6

    # Resolve to absolute path so find works regardless of cwd
    if [ -d "${base_dir}" ]; then
        base_dir=$(cd "${base_dir}" && pwd)
    fi

    if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
        echo ""
        return
    fi

    local deb_arch="${arch}"
    [ "${arch}" = "x86_64" ] && deb_arch="amd64"
    [ "${arch}" = "aarch64" ] && deb_arch="arm64"

    local lineage
    lineage=$(echo "${version}" | cut -d. -f1-2)

    # Exact filename patterns to try (deb: version_distro_arch and version_arch)
    local fname
    if [ "${pkg_type}" = "rpm" ]; then
        fname="aerospike-server-${edition}-${version}-1.${artifact_distro}.${arch}.rpm"
        for dir in "${base_dir}" "${base_dir}/${version}" "${base_dir}/${lineage}" "${base_dir}/${lineage}/${version}"; do
            [ -d "${dir}" ] || continue
            if [ -f "${dir}/${fname}" ]; then
                echo "${dir}/${fname}"
                return
            fi
        done
    else
        # deb: try version_distro_arch (e.g. 7.1.0.21-8ubuntu22.04_arm64) then version_arch
        # Explicit check at base_dir root first (common when -u ./artifacts points at dir with .deb files)
        if [ -d "${base_dir}" ]; then
            local exact="${base_dir}/aerospike-server-${edition}_${version}${artifact_distro}_${deb_arch}.deb"
            [ -f "${exact}" ] && echo "${exact}" && return
            exact="${base_dir}/aerospike-server-${edition}_${version}_${deb_arch}.deb"
            [ -f "${exact}" ] && echo "${exact}" && return
            # Glob in base_dir only: *edition*_*_arch.deb (matches version+distro or version in middle)
            local f
            for f in "${base_dir}"/*aerospike-server*"${edition}"*_"${deb_arch}".deb; do
                [ -f "${f}" ] && echo "${f}" && return
            done
        fi
        for fname in "aerospike-server-${edition}_${version}${artifact_distro}_${deb_arch}.deb" "aerospike-server-${edition}_${version}_${deb_arch}.deb"; do
            for dir in "${base_dir}" "${base_dir}/${version}" "${base_dir}/${lineage}" "${base_dir}/${lineage}/${version}"; do
                [ -d "${dir}" ] || continue
                if [ -f "${dir}/${fname}" ]; then
                    echo "${dir}/${fname}"
                    return
                fi
            done
        done
    fi

    # Fallback: glob for any server package matching edition and arch (e.g. version suffix differs)
    for dir in "${base_dir}" "${base_dir}/${version}" "${base_dir}/${lineage}" "${base_dir}/${lineage}/${version}"; do
        [ -d "${dir}" ] || continue
        local found
        if [ "${pkg_type}" = "rpm" ]; then
            found=$(find "${dir}" -maxdepth 1 -type f -name "aerospike-server-${edition}-*.${artifact_distro}.${arch}.rpm" 2>/dev/null | head -1)
            [ -z "${found}" ] && found=$(find "${dir}" -maxdepth 1 -type f -name "*aerospike-server*${edition}*${arch}.rpm" 2>/dev/null | head -1)
        else
            found=$(find "${dir}" -maxdepth 1 -type f -name "aerospike-server-${edition}_*_${deb_arch}.deb" 2>/dev/null | head -1)
            [ -z "${found}" ] && found=$(find "${dir}" -maxdepth 1 -type f -name "*aerospike-server*${edition}*${deb_arch}.deb" 2>/dev/null | head -1)
        fi
        if [ -n "${found}" ]; then
            echo "${found}"
            return
        fi
    done

    # Last resort: any file with edition and arch in name (e.g. custom naming)
    for dir in "${base_dir}" "${base_dir}/${version}" "${base_dir}/${lineage}" "${base_dir}/${lineage}/${version}"; do
        [ -d "${dir}" ] || continue
        local f
        if [ "${pkg_type}" = "rpm" ]; then
            for f in "${dir}"/*.rpm; do
                [ -f "${f}" ] || continue
                if [[ "${f}" = *"${edition}"* ]] && [[ "${f}" = *"${arch}"* ]] && [[ "${f}" = *server* ]]; then
                    echo "${f}"
                    return
                fi
            done
        else
            for f in "${dir}"/*.deb; do
                [ -f "${f}" ] || continue
                if [[ "${f}" = *"${edition}"* ]] && [[ "${f}" = *"${deb_arch}"* ]] && [[ "${f}" = *server* ]]; then
                    echo "${f}"
                    return
                fi
            done
        fi
    done

    # Recursive fallback: search under base_dir (handles nested layouts e.g. releases/7.1/.../pkg.deb)
    if [ -d "${base_dir}" ]; then
        local found
        if [ "${pkg_type}" = "rpm" ]; then
            found=$(find "${base_dir}" -type f -name "*aerospike-server*${edition}*${arch}.rpm" 2>/dev/null | head -1)
        else
            # Prefer edition-specific match, then any server package for this arch (e.g. version_distro in filename)
            found=$(find "${base_dir}" -type f -name "*aerospike-server*${edition}*${deb_arch}.deb" 2>/dev/null | head -1)
            [ -z "${found}" ] && found=$(find "${base_dir}" -type f -name "*aerospike-server*_*_${deb_arch}.deb" 2>/dev/null | head -1)
        fi
        if [ -n "${found}" ]; then
            echo "${found}"
            return
        fi
    fi
    echo ""
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
