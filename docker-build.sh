#!/usr/bin/env bash
#
# Generate and build Docker images for Aerospike server releases.
# Copyright 2014-2025 Aerospike, Inc. Licensed under the Apache License, Version 2.0.
# See LICENSE in the project root.
#
# Dependencies: lib/fetch.sh, lib/log.sh, lib/support.sh, lib/version.sh
# Flow: parse args -> generate_dockerfiles -> [generate_bake -> build]
#
# Generated RUN layers use curl retries and sleep/backoff for downloads; sustained
# outages on artifact hosts or GitHub can still fail builds after those attempts.
#

set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
cd "${SCRIPT_DIR}"

source lib/fetch.sh
source lib/log.sh
source lib/support.sh
source lib/version.sh

BAKE_FILE="bake-multi.hcl"

function usage() {
    cat <<EOF
Usage: $0 -t|-p|-g [OPTIONS] [version|lineage]

Generate Dockerfiles and build Docker images for Aerospike server releases.

MODE (one required):
    -t               Test mode - build and load locally (single platform per arch)
    -p               Push mode - build and push to registry (multi-arch manifest)
    -g, --generate   Generate Dockerfiles only (no build)

OPTIONS:
    -r, --registry REG  Container registry (and repo path) for push mode.
                        Image names: <REG>/aerospike-server[-edition]:<tag>
                        Multiple: repeat -r (e.g. -r reg1 -r reg2)
                        Default: aerospike (docker.io/aerospike/...)
                        Example: -r artifact.aerospike.io/database-docker-dev-local
    -u, --url URL       Custom artifacts URL
                        Default: https://download.aerospike.com/artifacts
                        If *.tgz is not found, falls back to *.rpm (el9/el10) or *.deb (ubuntu).
                        JFrog Artifactory RPM (el9/el10 layout):
                          https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local
                        DEB (flat layout): database-deb-prod-public-local or direct edition URL.
    -e, --edition ED    Filter edition(s): community, enterprise, federal
                        Can specify multiple: -e enterprise community
                        Default: all editions
    -d, --distro DIST   Filter distro(s): ubuntu22.04, ubuntu24.04, ubi9, ubi10
                        Prefix match: -d ubuntu (all Ubuntu), -d ubi (all UBI)
                        Can specify multiple: -d ubuntu24.04 ubi9
                        Default: all distros supported by lineage
    -a, --arch ARCH     Filter architecture(s): amd64, arm64 (or x86_64, aarch64)
                        Can specify multiple: -a amd64 arm64
                        Default: all platforms (linux/amd64, linux/arm64; federal is amd64 only)
    -T, --timestamp TS  Use TS for push tags (e.g. version-TS). Format: YYYYMMDDHHMMSS
                        Default: current UTC time
    --no-cache          Disable Docker build cache (force full rebuild)
    -h, --help          Show this help message

VERSION/LINEAGE:
    (none)                         Build all supported lineages (7.1, 7.2, 8.0, 8.1)
    8.1                            Lineage - auto-detects latest 8.1.x version
    8.1.1.0                        Specific release version
    8.1.1.0-rc2                    Release candidate
    8.1.1.0-start-16               Development build
    8.1.1.0-start-16-gea126d3      Development build with git hash

DISTRO SUPPORT BY LINEAGE (default: all distros below; primary UBI is ubi9):
    7.1:       ubuntu22.04, ubi9
    7.2, 8.0:  ubuntu24.04, ubi9
    8.1+:      ubuntu24.04, ubi9, ubi10

OUTPUT:
    releases/<lineage>/<edition>/<distro>/    Generated Dockerfiles
    bake-multi.hcl                            Docker buildx bake file

EXAMPLES:
    # Build all editions/distros for lineage 8.1 (local test)
    $0 -t 8.1

    # Build specific edition and distro
    $0 -t 8.1 -e enterprise -d ubuntu24.04

    # Build multiple editions and distros
    $0 -t 8.1 -e enterprise community -d ubuntu24.04 ubi9

    # Build for specific architecture(s) only
    $0 -t 8.1 -a amd64
    $0 -t 8.1 -a arm64
    $0 -p 8.1 -a amd64 arm64

    # Build and push to registry
    $0 -p 8.1 -e enterprise federal

    # Build and push to one or more registries
    $0 -p 8.1 -e enterprise -r artifact.aerospike.io/database-docker-dev-local
    $0 -p 8.1 -e enterprise -r reg1 -r reg2

    # Push with custom timestamp for tags (e.g. product:8.1.1.1-20250225120000)
    $0 -p 8.1 -T 20250225120000

    # Generate Dockerfiles only (no build)
    $0 -g 8.1

    # Build from custom/staging artifacts server
    $0 -t 8.1.1.0-start-108 -e enterprise -d ubi9 \\
       -u https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise

    # Build all supported lineages
    $0 -g
EOF
}

#------------------------------------------------------------------------------
# Generate Dockerfiles
#------------------------------------------------------------------------------

# Emit the inline RUN block for Debian/Ubuntu-based images.
# Quoted heredocs prevent shell expansion; content is Docker build-time.
#
# LDAP fallback: Ubuntu 24.04 no longer ships libldap-2.5-0 or libldap-2.4-2.
# When needed, we temporarily add Focal/Jammy official repos with [trusted=yes]
# to skip GPG key setup (keys are not in the minimal base image). The repos are
# removed immediately after install. This is acceptable because (a) we pull only
# libldap packages, (b) the repos are canonical Ubuntu archive mirrors, and
# (c) the sources.list entries are deleted before the layer is committed.
# Operational note: if Ubuntu renames/removes libldap packages or archive paths,
# the apt-cache gates or focal/jammy fallback lines may need updating; failures
# surface at install or at the liblber check rather than silently skipping LDAP.
#
# Shared Dockerfile RUN fragments (quoted heredocs = Docker build-time shell).
# Reduces duplicated LDAP / compat-lib / tools / cleanup logic across DEB branches.
function _emit_deb_ldap_enterprise() {
    local mirror_kind=$1
    cat <<'EMIT'
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      if apt-cache show libldap-2.5-0 >/dev/null 2>&1; then \
        if ! apt-get install -y --no-install-recommends libldap-2.5-0; then \
          echo "Note: libldap-2.5-0 available but not installable"; \
        fi; \
      fi; \
      if apt-cache show libldap-2.4-2 >/dev/null 2>&1; then \
        if ! apt-get install -y --no-install-recommends libldap-2.4-2; then \
          echo "Note: libldap-2.4-2 available but not installable"; \
        fi; \
      fi; \
      if ! dpkg --configure -a; then true; fi; \
      if ! { ls /usr/lib/*/liblber-2.4.so.2 >/dev/null 2>&1 || ls /usr/lib/*/liblber-2.5.so.0 >/dev/null 2>&1; }; then \
EMIT
    case "${mirror_kind}" in
    amd64)
        cat <<'EMIT'
        echo "deb [trusted=yes] http://archive.ubuntu.com/ubuntu focal main" > /etc/apt/sources.list.d/focal-ldap.list; \
        echo "deb [trusted=yes] http://archive.ubuntu.com/ubuntu jammy main" > /etc/apt/sources.list.d/jammy-ldap.list; \
EMIT
        ;;
    arm64)
        cat <<'EMIT'
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports focal main" > /etc/apt/sources.list.d/focal-ldap.list; \
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports jammy main" > /etc/apt/sources.list.d/jammy-ldap.list; \
EMIT
        ;;
    multi)
        cat <<'EMIT'
        if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
          ldap_repo="http://archive.ubuntu.com/ubuntu"; \
        else \
          ldap_repo="http://ports.ubuntu.com/ubuntu-ports"; \
        fi; \
        echo "deb [trusted=yes] ${ldap_repo} focal main" > /etc/apt/sources.list.d/focal-ldap.list; \
        echo "deb [trusted=yes] ${ldap_repo} jammy main" > /etc/apt/sources.list.d/jammy-ldap.list; \
EMIT
        ;;
    multi_native)
        cat <<'EMIT'
        if [ "${ARCH}" = "amd64" ]; then \
          ldap_repo="http://archive.ubuntu.com/ubuntu"; \
        else \
          ldap_repo="http://ports.ubuntu.com/ubuntu-ports"; \
        fi; \
        echo "deb [trusted=yes] ${ldap_repo} focal main" > /etc/apt/sources.list.d/focal-ldap.list; \
        echo "deb [trusted=yes] ${ldap_repo} jammy main" > /etc/apt/sources.list.d/jammy-ldap.list; \
EMIT
        ;;
    esac
    cat <<'EMIT'
        apt-get update -y; \
        if apt-cache show libldap-2.5-0 >/dev/null 2>&1; then \
          if ! apt-get install -y --no-install-recommends libldap-2.5-0; then \
            echo "Note: libldap-2.5-0 available but not installable from fallback repos"; \
          fi; \
        fi; \
        if apt-cache show libldap-2.4-2 >/dev/null 2>&1; then \
          if ! apt-get install -y --no-install-recommends libldap-2.4-2; then \
            echo "Note: libldap-2.4-2 available but not installable from fallback repos"; \
          fi; \
        fi; \
        if ! dpkg --configure -a; then true; fi; \
        rm -f /etc/apt/sources.list.d/focal-ldap.list /etc/apt/sources.list.d/jammy-ldap.list; \
      fi; \
      { ls /usr/lib/*/liblber-2.4.so.2 >/dev/null 2>&1 || ls /usr/lib/*/liblber-2.5.so.0 >/dev/null 2>&1; } || { echo "ERROR: liblber not found - libldap install failed" >&2; exit 1; }; \
    fi; \
EMIT
}

function _emit_deb_compat_tgz() {
    cat <<'EMIT'
    if [ "${AEROSPIKE_COMPAT_LIBS}" = "1" ]; then \
      curl_pkg="libcurl4"; \
      apt-cache show libcurl4t64 >/dev/null 2>&1 && curl_pkg="libcurl4t64"; \
      for cpkg in libssl1.1 "${curl_pkg}"; do \
        if apt-cache show "${cpkg}" >/dev/null 2>&1; then \
          if ! apt-get install -y --no-install-recommends "${cpkg}"; then \
            echo "Note: ${cpkg} available but not installable"; \
          fi; \
        fi; \
      done; \
      if ! dpkg --configure -a; then true; fi; \
    fi; \
EMIT
}

function _emit_deb_compat_native() {
    local repo_kind=$1
    cat <<'EMIT'
    if [ "${AEROSPIKE_COMPAT_LIBS}" = "1" ]; then \
      . /etc/os-release; \
      if [ "${ID:-}" = "ubuntu" ]; then \
EMIT
    case "${repo_kind}" in
    amd64)
        cat <<'EMIT'
        echo "deb [trusted=yes] http://archive.ubuntu.com/ubuntu focal main" > /etc/apt/sources.list.d/focal-compat.list; \
        [ "${VERSION_ID}" != "22.04" ] && \
          echo "deb [trusted=yes] http://archive.ubuntu.com/ubuntu jammy main" > /etc/apt/sources.list.d/jammy-compat.list; \
EMIT
        ;;
    arm64)
        cat <<'EMIT'
        echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports focal main" > /etc/apt/sources.list.d/focal-compat.list; \
        [ "${VERSION_ID}" != "22.04" ] && \
          echo "deb [trusted=yes] http://ports.ubuntu.com/ubuntu-ports jammy main" > /etc/apt/sources.list.d/jammy-compat.list; \
EMIT
        ;;
    multi_native)
        cat <<'EMIT'
        if [ "${ARCH}" = "amd64" ]; then \
          repo_url="http://archive.ubuntu.com/ubuntu"; \
        else \
          repo_url="http://ports.ubuntu.com/ubuntu-ports"; \
        fi; \
        echo "deb [trusted=yes] ${repo_url} focal main" > /etc/apt/sources.list.d/focal-compat.list; \
        [ "${VERSION_ID}" != "22.04" ] && \
          echo "deb [trusted=yes] ${repo_url} jammy main" > /etc/apt/sources.list.d/jammy-compat.list; \
EMIT
        ;;
    esac
    cat <<'EMIT'
        apt-get update -y; \
        if ! dpkg --configure -a; then true; fi; \
        curl_pkg="libcurl4"; \
        apt-cache show libcurl4t64 >/dev/null 2>&1 && curl_pkg="libcurl4t64"; \
        for cpkg in libssl1.1 "${curl_pkg}" libldap-2.4-2 libldap-2.5-0; do \
          if apt-cache show "${cpkg}" >/dev/null 2>&1; then \
            if ! apt-get install -y --no-install-recommends "${cpkg}"; then \
              echo "Note: ${cpkg} available but not installable"; \
            fi; \
          fi; \
        done; \
        if ! dpkg --configure -a; then true; fi; \
        if ! ldconfig; then true; fi; \
        if ! ldconfig -p 2>/dev/null | grep -q libcrypto.so.1.1; then \
          rm -f /var/cache/apt/archives/*.deb 2>/dev/null; \
          curl_pkg="libcurl4"; \
          apt-cache show libcurl4t64 >/dev/null 2>&1 && curl_pkg="libcurl4t64"; \
          for cpkg in libssl1.1 "${curl_pkg}" libldap-2.4-2 libldap-2.5-0; do \
            if apt-cache show "${cpkg}" >/dev/null 2>&1; then \
              if ! apt-get install -y --no-install-recommends --download-only "${cpkg}" 2>/dev/null; then true; fi; \
            fi; \
          done; \
          if ls /var/cache/apt/archives/*.deb >/dev/null 2>&1; then \
            if ! dpkg -i /var/cache/apt/archives/*.deb; then \
              echo "Note: some compat lib debs could not be installed"; \
            fi; \
          fi; \
          if ! dpkg --configure -a; then true; fi; \
        fi; \
        rm -f /etc/apt/sources.list.d/focal-compat.list /etc/apt/sources.list.d/jammy-compat.list; \
      fi; \
    fi; \
EMIT
}

function _emit_deb_tgz_tools_extract_layout() {
    cat <<'EMIT'
  { \
    ar -x aerospike/aerospike-tools*.deb --output aerospike/pkg; \
    tar xf aerospike/pkg/data.tar.xz -C aerospike/pkg/; \
  }; \
  { \
    find aerospike/pkg/opt/aerospike/bin/ -user aerospike -group aerospike -exec chown root:root {} +; \
    mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike; \
    if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/; \
    else \
      mkdir -p /usr/lib/asadm; \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/; \
    fi; \
    ln -snf /usr/lib/asadm/asadm /usr/bin/asadm; \
    if [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ]; then \
      mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/; \
    fi; \
    ln -snf /usr/lib/asadm/asinfo /usr/bin/asinfo; \
  }; \
EMIT
}

function _emit_deb_cleanup_tgz_build_deps() {
    cat <<'EMIT'
  { \
    for pkg in binutils xz-utils curl procps; do \
      if ! dpkg --purge "${pkg}"; then \
        echo "Note: keeping ${pkg} (has reverse dependencies)"; \
      fi; \
    done; \
    if ! apt-get autoremove -y; then true; fi; \
    rm -rf /var/lib/apt/lists/*; \
    unset DEBIAN_FRONTEND; \
  }; \
EMIT
}

function _emit_deb_cleanup_native_curl() {
    cat <<'EMIT'
  { \
    rm -f server.deb; \
    if ! dpkg --purge curl; then \
      echo "Note: keeping curl (has reverse dependencies)"; \
    fi; \
    if ! apt-get autoremove -y; then true; fi; \
    rm -rf /var/lib/apt/lists/*; \
    unset DEBIAN_FRONTEND; \
  }; \
EMIT
}

# RPM tgz: classic rpm2cpio + tools layout (amd64 and multi-aarch64/amd64 host).
# Resolve tools RPM by basename (reliable glob); extract with cpio -D (avoids subshell cd / hadolint DL3003).
function _emit_rpm_tgz_tools_layout_classic() {
    cat <<'EMIT'
  { \
    shopt -s nullglob; \
    _tool_rpms=(aerospike/aerospike-tools*.rpm); \
    if [ "${#_tool_rpms[@]}" -eq 0 ]; then \
      echo "ERROR: no aerospike-tools*.rpm under aerospike/ after tar extract (cwd=$(pwd))" >&2; \
      if ! ls -la aerospike >&2; then true; fi; \
      exit 1; \
    fi; \
    _tool_rpm_base="${_tool_rpms[0]##*/}"; \
    if ! rpm2cpio "aerospike/${_tool_rpm_base}" | cpio -idm -D aerospike/pkg; then \
      sleep 3; \
      rpm2cpio "aerospike/${_tool_rpm_base}" | cpio -idm -D aerospike/pkg; \
    fi; \
  }; \
  { \
    if [ -d aerospike/pkg/opt/aerospike/bin/ ]; then \
      find aerospike/pkg/opt/aerospike/bin/ -exec chown root:root {} +; \
    fi; \
    mkdir -p /etc/aerospike; \
    if [ -f aerospike/pkg/etc/aerospike/astools.conf ]; then \
      mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike/; \
    fi; \
    if [ ! -e aerospike/pkg/opt/aerospike/bin/asadm ]; then \
      echo "ERROR: asadm missing under aerospike/pkg/opt/aerospike/bin after tools extract" >&2; \
      find aerospike/pkg -maxdepth 6 \( -name asadm -o -name asinfo \) -print >&2; \
      exit 1; \
    fi; \
    if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/; \
    else \
      mkdir -p /usr/lib/asadm; \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/; \
    fi; \
    if [ -e /usr/lib/asadm/asadm ]; then \
      ln -snf /usr/lib/asadm/asadm /usr/bin/asadm; \
    fi; \
    if [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ]; then \
      mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/; \
    fi; \
    if [ -e /usr/lib/asadm/asinfo ]; then \
      ln -snf /usr/lib/asadm/asinfo /usr/bin/asinfo; \
    fi; \
  }; \
EMIT
}

function _emit_rpm_tgz_rm_aerospike_and_microdnf_clean() {
    cat <<'EMIT'
  { \
    rm -rf aerospike; \
  }; \
  { \
    if ! microdnf remove -y findutils tar gzip xz cpio; then true; fi; \
    if ! microdnf clean all; then true; fi; \
    rm -rf /var/cache/yum /var/cache/dnf; \
  }; \
EMIT
}

function _append_run_deb() {
    local pkg_format=$1 single_arch=${2:-}
    if [ "${pkg_format}" = "tgz" ]; then
        if [ "${single_arch}" = "amd64" ]; then
            cat <<'RUNBLOCK'
# Install Aerospike Server and Tools
# hadolint ignore=DL3008
RUN \
  { \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends \
      binutils xz-utils ca-certificates curl procps; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static" --output /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static" --output /usr/bin/as-tini-static; \
    fi; \
    echo "d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940 /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    mkdir -p aerospike/pkg; \
    pkg_link="${AEROSPIKE_X86_64_LINK}"; \
    sha256="${AEROSPIKE_SHA_X86_64}"; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
      sleep 5; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
        echo "Could not fetch pkg - ${pkg_link}" >&2; \
        exit 1; \
      fi; \
    fi; \
    echo "${sha256} aerospike-server.tgz" | sha256sum -c -; \
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike; \
    rm aerospike-server.tgz; \
    mkdir -p /var/{log,run}/aerospike; \
    mkdir -p /etc/aerospike; \
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      if [ -f aerospike/features.conf ]; then \
        cp aerospike/features.conf /etc/aerospike/features.conf; \
      elif [ -f aerospike/etc/aerospike/features.conf ]; then \
        cp aerospike/etc/aerospike/features.conf /etc/aerospike/features.conf; \
      fi; \
    fi; \
  }; \
  { \
RUNBLOCK
            _emit_deb_ldap_enterprise amd64
            _emit_deb_compat_tgz
            cat <<'RUNBLOCK'
    dpkg -i aerospike/aerospike-server-*.deb; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    rm -rf /opt/aerospike/bin; \
  }; \
RUNBLOCK
            _emit_deb_tgz_tools_extract_layout
            cat <<'RUNBLOCK'
  { \
    rm -rf aerospike; \
  }; \
RUNBLOCK
            _emit_deb_cleanup_tgz_build_deps
            cat <<'RUNBLOCK'
  echo "done";

RUNBLOCK
        elif [ "${single_arch}" = "arm64" ]; then
            cat <<'RUNBLOCK'
# Install Aerospike Server and Tools (arm64)
# hadolint ignore=DL3008
RUN \
  { \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -y; \
    if ! apt-get install -y --no-install-recommends \
      binutils xz-utils ca-certificates curl procps; then \
      if ! dpkg --configure -a; then true; fi; \
      sleep 2; \
      if ! dpkg --configure -a; then true; fi; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64" --output /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64" --output /usr/bin/as-tini-static; \
    fi; \
    echo "1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    mkdir -p aerospike/pkg; \
    pkg_link="${AEROSPIKE_AARCH64_LINK}"; \
    sha256="${AEROSPIKE_SHA_AARCH64}"; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
      sleep 5; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
        echo "Could not fetch pkg - ${pkg_link}" >&2; \
        exit 1; \
      fi; \
    fi; \
    echo "${sha256} aerospike-server.tgz" | sha256sum -c -; \
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike; \
    rm aerospike-server.tgz; \
    mkdir -p /var/{log,run}/aerospike; \
    mkdir -p /etc/aerospike; \
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      if [ -f aerospike/features.conf ]; then \
        cp aerospike/features.conf /etc/aerospike/features.conf; \
      elif [ -f aerospike/etc/aerospike/features.conf ]; then \
        cp aerospike/etc/aerospike/features.conf /etc/aerospike/features.conf; \
      fi; \
    fi; \
  }; \
  { \
RUNBLOCK
            _emit_deb_ldap_enterprise arm64
            _emit_deb_compat_tgz
            cat <<'RUNBLOCK'
    if ! dpkg -i aerospike/aerospike-server-*.deb; then \
      if ! dpkg --configure -a; then true; fi; \
      sleep 2; \
    fi; \
    if ! dpkg --configure -a; then true; fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    rm -rf /opt/aerospike/bin; \
  }; \
RUNBLOCK
            _emit_deb_tgz_tools_extract_layout
            cat <<'RUNBLOCK'
  { \
    rm -rf aerospike; \
  }; \
RUNBLOCK
            _emit_deb_cleanup_tgz_build_deps
            cat <<'RUNBLOCK'
  echo "done";

RUNBLOCK
        else
            cat <<'RUNBLOCK'
# Install Aerospike Server and Tools
# hadolint ignore=DL3008
RUN \
  { \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -y; \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
      if ! apt-get install -y --no-install-recommends \
        binutils xz-utils ca-certificates curl procps; then \
        if ! dpkg --configure -a; then true; fi; \
        sleep 2; \
        if ! dpkg --configure -a; then true; fi; \
      fi; \
    else \
      apt-get install -y --no-install-recommends \
        binutils xz-utils ca-certificates curl procps; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "${ARCH}" = "amd64" ]; then \
      sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
      suffix=""; \
    elif [ "${ARCH}" = "arm64" ]; then \
      sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b; \
      suffix="-arm64"; \
    else \
      echo "Unsupported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" --output /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" --output /usr/bin/as-tini-static; \
    fi; \
    echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    ARCH="$(dpkg --print-architecture)"; \
    mkdir -p aerospike/pkg; \
    if [ "${ARCH}" = "amd64" ]; then \
      pkg_link="${AEROSPIKE_X86_64_LINK}"; \
      sha256="${AEROSPIKE_SHA_X86_64}"; \
    elif [ "${ARCH}" = "arm64" ]; then \
      pkg_link="${AEROSPIKE_AARCH64_LINK}"; \
      sha256="${AEROSPIKE_SHA_AARCH64}"; \
    else \
      echo "Unsupported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
      sleep 5; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
        echo "Could not fetch pkg - ${pkg_link}" >&2; \
        exit 1; \
      fi; \
    fi; \
    echo "${sha256} aerospike-server.tgz" | sha256sum -c -; \
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike; \
    rm aerospike-server.tgz; \
    mkdir -p /var/{log,run}/aerospike; \
    mkdir -p /etc/aerospike; \
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      if [ -f aerospike/features.conf ]; then \
        cp aerospike/features.conf /etc/aerospike/features.conf; \
      elif [ -f aerospike/etc/aerospike/features.conf ]; then \
        cp aerospike/etc/aerospike/features.conf /etc/aerospike/features.conf; \
      fi; \
    fi; \
  }; \
  { \
RUNBLOCK
            _emit_deb_ldap_enterprise multi
            _emit_deb_compat_tgz
            cat <<'RUNBLOCK'
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
      if ! dpkg -i aerospike/aerospike-server-*.deb; then \
        if ! dpkg --configure -a; then true; fi; \
        sleep 2; \
      fi; \
      if ! dpkg --configure -a; then true; fi; \
    else \
      dpkg -i aerospike/aerospike-server-*.deb; \
    fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    rm -rf /opt/aerospike/bin; \
  }; \
RUNBLOCK
            _emit_deb_tgz_tools_extract_layout
            cat <<'RUNBLOCK'
  { \
    rm -rf aerospike; \
  }; \
RUNBLOCK
            _emit_deb_cleanup_tgz_build_deps
            cat <<'RUNBLOCK'
  echo "done";

RUNBLOCK
        fi
    else
        if [ "${single_arch}" = "amd64" ]; then
            cat <<'RUNBLOCK'
# Install Aerospike Server
# hadolint ignore=DL3008
RUN \
  { \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static" --output /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static" --output /usr/bin/as-tini-static; \
    fi; \
    echo "d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940 /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    if [ "${AEROSPIKE_LOCAL_PKG:-0}" = "1" ]; then \
      cp /tmp/server_amd64.deb server.deb; \
      if [ -f /tmp/server_amd64.deb.sha256 ]; then \
        hash=$(awk '{print $1}' /tmp/server_amd64.deb.sha256); \
        echo "${hash}  server.deb" | sha256sum -c -; \
      fi; \
    else \
      pkg_link="${AEROSPIKE_X86_64_LINK}"; \
      sha256="${AEROSPIKE_SHA_X86_64}"; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.deb; then \
        sleep 5; \
        curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.deb; \
      fi; \
      [ -n "${sha256}" ] && echo "${sha256} server.deb" | sha256sum -c -; \
    fi; \
RUNBLOCK
            _emit_deb_ldap_enterprise amd64
            _emit_deb_compat_native amd64
            cat <<'RUNBLOCK'
    dpkg -i server.deb; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    mkdir -p /var/{log,run}/aerospike; \
  }; \
RUNBLOCK
            _emit_deb_cleanup_native_curl
            cat <<'RUNBLOCK'
  echo "done";

RUNBLOCK
        elif [ "${single_arch}" = "arm64" ]; then
            cat <<'RUNBLOCK'
# Install Aerospike Server (arm64)
# hadolint ignore=DL3008
RUN \
  { \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -y; \
    if ! apt-get install -y --no-install-recommends ca-certificates curl; then \
      if ! dpkg --configure -a; then true; fi; \
      sleep 2; \
      if ! dpkg --configure -a; then true; fi; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64" --output /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64" --output /usr/bin/as-tini-static; \
    fi; \
    echo "1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    if [ "${AEROSPIKE_LOCAL_PKG:-0}" = "1" ]; then \
      cp /tmp/server_arm64.deb server.deb; \
      if [ -f /tmp/server_arm64.deb.sha256 ]; then \
        hash=$(awk '{print $1}' /tmp/server_arm64.deb.sha256); \
        echo "${hash}  server.deb" | sha256sum -c -; \
      fi; \
    else \
      pkg_link="${AEROSPIKE_AARCH64_LINK}"; \
      sha256="${AEROSPIKE_SHA_AARCH64}"; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.deb; then \
        sleep 5; \
        curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.deb; \
      fi; \
      [ -n "${sha256}" ] && echo "${sha256} server.deb" | sha256sum -c -; \
    fi; \
RUNBLOCK
            _emit_deb_ldap_enterprise arm64
            _emit_deb_compat_native arm64
            cat <<'RUNBLOCK'
    if ! dpkg -i server.deb; then \
      if ! dpkg --configure -a; then true; fi; \
      sleep 2; \
    fi; \
    if ! dpkg --configure -a; then true; fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    mkdir -p /var/{log,run}/aerospike; \
  }; \
RUNBLOCK
            _emit_deb_cleanup_native_curl
            cat <<'RUNBLOCK'
  echo "done";

RUNBLOCK
        else
            cat <<'RUNBLOCK'
# Install Aerospike Server
# hadolint ignore=DL3008
RUN \
  { \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -y; \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
      if ! apt-get install -y --no-install-recommends ca-certificates curl; then \
        if ! dpkg --configure -a; then true; fi; \
        sleep 2; \
        if ! dpkg --configure -a; then true; fi; \
      fi; \
    else \
      apt-get install -y --no-install-recommends ca-certificates curl; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "${ARCH}" = "amd64" ]; then \
      sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
      suffix=""; \
    elif [ "${ARCH}" = "arm64" ]; then \
      sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b; \
      suffix="-arm64"; \
    else \
      echo "Unsupported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" --output /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" --output /usr/bin/as-tini-static; \
    fi; \
    echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "${AEROSPIKE_LOCAL_PKG:-0}" = "1" ]; then \
      if [ "${ARCH}" = "amd64" ]; then \
        cp /tmp/server_amd64.deb server.deb; \
        if [ -f /tmp/server_amd64.deb.sha256 ]; then \
          hash=$(awk '{print $1}' /tmp/server_amd64.deb.sha256); \
          echo "${hash}  server.deb" | sha256sum -c -; \
        fi; \
      else \
        cp /tmp/server_arm64.deb server.deb; \
        if [ -f /tmp/server_arm64.deb.sha256 ]; then \
          hash=$(awk '{print $1}' /tmp/server_arm64.deb.sha256); \
          echo "${hash}  server.deb" | sha256sum -c -; \
        fi; \
      fi; \
    else \
      if [ "${ARCH}" = "amd64" ]; then \
        pkg_link="${AEROSPIKE_X86_64_LINK}"; \
        sha256="${AEROSPIKE_SHA_X86_64}"; \
      else \
        pkg_link="${AEROSPIKE_AARCH64_LINK}"; \
        sha256="${AEROSPIKE_SHA_AARCH64}"; \
      fi; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.deb; then \
        sleep 5; \
        curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.deb; \
      fi; \
      [ -n "${sha256}" ] && echo "${sha256} server.deb" | sha256sum -c -; \
    fi; \
RUNBLOCK
            _emit_deb_ldap_enterprise multi_native
            _emit_deb_compat_native multi_native
            cat <<'RUNBLOCK'
    if [ "${ARCH}" = "arm64" ]; then \
      if ! dpkg -i server.deb; then \
        if ! dpkg --configure -a; then true; fi; \
        sleep 2; \
      fi; \
      if ! dpkg --configure -a; then true; fi; \
    else \
      dpkg -i server.deb; \
    fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    mkdir -p /var/{log,run}/aerospike; \
  }; \
RUNBLOCK
            _emit_deb_cleanup_native_curl
            cat <<'RUNBLOCK'
  echo "done";

RUNBLOCK
        fi
    fi
}

# Emit the inline RUN block for UBI/RHEL-based images.
# _retry helper is defined inline (inside RUN) for arm64/multi-arch blocks to
# handle transient QEMU emulation failures on microdnf/rpm operations.
# Curl: UBI minimal ships curl-minimal; installing package "curl" conflicts on UBI 9+.
# We install curl-minimal (or full curl as fallback) only when /usr/bin/curl is missing.
function _append_run_rpm() {
    local pkg_format=$1 single_arch=${2:-}
    if [ "${pkg_format}" = "tgz" ]; then
        if [ "${single_arch}" = "amd64" ]; then
            cat <<'RUNBLOCK'
# Install Aerospike Server and Tools (amd64)
# hadolint ignore=DL3041
RUN \
  { \
    microdnf install -y --setopt=install_weak_deps=0 \
      findutils \
      tar \
      gzip \
      xz \
      ca-certificates \
      cpio \
      shadow-utils; \
  }; \
  { \
    if ! command -v curl >/dev/null 2>&1; then \
      if ! microdnf install -y curl-minimal; then \
        microdnf install -y curl; \
      fi; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static" -o /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static" -o /usr/bin/as-tini-static; \
    fi; \
    echo "d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940 /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    mkdir -p aerospike/pkg; \
    pkg_link="${AEROSPIKE_X86_64_LINK}"; \
    sha256="${AEROSPIKE_SHA_X86_64}"; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
      sleep 5; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
        echo "Could not fetch pkg - ${pkg_link}" >&2; \
        exit 1; \
      fi; \
    fi; \
    echo "${sha256} aerospike-server.tgz" | sha256sum -c -; \
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike; \
    rm aerospike-server.tgz; \
    mkdir -p /var/{log,run}/aerospike; \
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
  }; \
  { \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      microdnf install -y --setopt=install_weak_deps=0 openldap; \
    fi; \
    if ! rpm -i --excludedocs aerospike/aerospike-server-*.rpm; then \
      sleep 3; \
      if ! rpm -i --force --excludedocs aerospike/aerospike-server-*.rpm; then \
        sleep 5; \
        rpm -i --force --nodeps --excludedocs aerospike/aerospike-server-*.rpm; \
      fi; \
    fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    rm -rf /opt/aerospike/bin; \
  }; \
RUNBLOCK
            _emit_rpm_tgz_tools_layout_classic
            _emit_rpm_tgz_rm_aerospike_and_microdnf_clean
            cat <<'RUNBLOCK'
  echo "done";

RUNBLOCK
        elif [ "${single_arch}" = "arm64" ]; then
            cat <<'RUNBLOCK'
# Install Aerospike Server and Tools (arm64)
# hadolint ignore=DL3041
RUN \
  _retry() { local _i; for _i in 1 2 3 4 5; do if "$@"; then return 0; fi; sleep $((_i*5)); done; "$@"; }; \
  { \
    _retry microdnf install -y --setopt=install_weak_deps=0 \
      findutils \
      tar \
      gzip \
      xz \
      ca-certificates \
      cpio \
      shadow-utils; \
  }; \
  { \
    if ! command -v curl >/dev/null 2>&1; then \
      if ! microdnf install -y curl-minimal; then \
        microdnf install -y curl; \
      fi; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64" -o /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64" -o /usr/bin/as-tini-static; \
    fi; \
    echo "1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    mkdir -p aerospike/pkg; \
    pkg_link="${AEROSPIKE_AARCH64_LINK}"; \
    sha256="${AEROSPIKE_SHA_AARCH64}"; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
      sleep 5; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
        echo "Could not fetch pkg - ${pkg_link}" >&2; \
        exit 1; \
      fi; \
    fi; \
    echo "${sha256} aerospike-server.tgz" | sha256sum -c -; \
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike; \
    rm aerospike-server.tgz; \
    mkdir -p /var/{log,run}/aerospike; \
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
  }; \
  { \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      _retry microdnf install -y --setopt=install_weak_deps=0 openldap; \
    fi; \
    if ! rpm -i --excludedocs aerospike/aerospike-server-*.rpm; then \
      sleep 3; \
      if ! rpm -i --force --excludedocs aerospike/aerospike-server-*.rpm; then \
        sleep 5; \
        rpm -i --force --nodeps --excludedocs aerospike/aerospike-server-*.rpm; \
      fi; \
    fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    rm -rf /opt/aerospike/bin; \
  }; \
  { \
    _rpm="aerospike/aerospike-tools*.rpm"; \
    if ! rpm2cpio aerospike/${_rpm##*/} | cpio -idm -D aerospike/pkg; then \
      sleep 3; \
      rpm2cpio aerospike/${_rpm##*/} | cpio -idm -D aerospike/pkg; \
    fi; \
  }; \
  { \
    if [ -d aerospike/pkg/opt/aerospike/bin/ ]; then \
      find aerospike/pkg/opt/aerospike/bin/ -exec chown root:root {} +; \
    fi; \
    mkdir -p /etc/aerospike; \
    if [ -f aerospike/pkg/etc/aerospike/astools.conf ]; then \
      mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike/; \
    fi; \
    if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/; \
    else \
      mkdir -p /usr/lib/asadm; \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/; \
    fi; \
    if [ -e /usr/lib/asadm/asadm ]; then \
      ln -snf /usr/lib/asadm/asadm /usr/bin/asadm; \
    fi; \
    if [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ]; then \
      mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/; \
    fi; \
    if [ -e /usr/lib/asadm/asinfo ]; then \
      ln -snf /usr/lib/asadm/asinfo /usr/bin/asinfo; \
    fi; \
  }; \
  { \
    rm -rf aerospike; \
  }; \
  { \
    if ! microdnf remove -y findutils tar gzip xz cpio; then true; fi; \
    if ! microdnf clean all; then true; fi; \
    rm -rf /var/cache/yum /var/cache/dnf; \
  }; \
  echo "done";

RUNBLOCK
        else
            cat <<'RUNBLOCK'
# Install Aerospike Server and Tools
# hadolint ignore=DL3041
RUN \
  _retry() { local _i; for _i in 1 2 3 4 5; do if "$@"; then return 0; fi; sleep $((_i*5)); done; "$@"; }; \
  { \
    _retry microdnf install -y --setopt=install_weak_deps=0 \
      findutils \
      tar \
      gzip \
      xz \
      ca-certificates \
      cpio \
      shadow-utils; \
  }; \
  { \
    if ! command -v curl >/dev/null 2>&1; then \
      if ! microdnf install -y curl-minimal; then \
        microdnf install -y curl; \
      fi; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    ARCH="$(uname -m)"; \
    if [ "${ARCH}" = "x86_64" ]; then \
      sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
      suffix=""; \
    elif [ "${ARCH}" = "aarch64" ]; then \
      sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b; \
      suffix="-arm64"; \
    else \
      echo "Unsupported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" -o /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" -o /usr/bin/as-tini-static; \
    fi; \
    echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    ARCH="$(uname -m)"; \
    mkdir -p aerospike/pkg; \
    if [ "${ARCH}" = "x86_64" ]; then \
      pkg_link="${AEROSPIKE_X86_64_LINK}"; \
      sha256="${AEROSPIKE_SHA_X86_64}"; \
    elif [ "${ARCH}" = "aarch64" ]; then \
      pkg_link="${AEROSPIKE_AARCH64_LINK}"; \
      sha256="${AEROSPIKE_SHA_AARCH64}"; \
    else \
      echo "Unsupported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
      sleep 5; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
        echo "Could not fetch pkg - ${pkg_link}" >&2; \
        exit 1; \
      fi; \
    fi; \
    echo "${sha256} aerospike-server.tgz" | sha256sum -c -; \
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike; \
    rm aerospike-server.tgz; \
    mkdir -p /var/{log,run}/aerospike; \
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
  }; \
  { \
    ARCH="$(uname -m)"; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      _retry microdnf install -y --setopt=install_weak_deps=0 openldap; \
    fi; \
    if ! rpm -i --excludedocs aerospike/aerospike-server-*.rpm; then \
      sleep 3; \
      if ! rpm -i --force --excludedocs aerospike/aerospike-server-*.rpm; then \
        sleep 5; \
        rpm -i --force --nodeps --excludedocs aerospike/aerospike-server-*.rpm; \
      fi; \
    fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    rm -rf /opt/aerospike/bin; \
  }; \
RUNBLOCK
            _emit_rpm_tgz_tools_layout_classic
            _emit_rpm_tgz_rm_aerospike_and_microdnf_clean
            cat <<'RUNBLOCK'
  echo "done";

RUNBLOCK
        fi
    else
        if [ "${single_arch}" = "amd64" ]; then
            cat <<'RUNBLOCK'
# Install Aerospike Server (amd64)
# hadolint ignore=DL3041
RUN \
  { \
    microdnf install -y --setopt=install_weak_deps=0 ca-certificates shadow-utils; \
  }; \
  { \
    if ! command -v curl >/dev/null 2>&1; then \
      if ! microdnf install -y curl-minimal; then \
        microdnf install -y curl; \
      fi; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static" -o /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static" -o /usr/bin/as-tini-static; \
    fi; \
    echo "d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940 /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    if [ "${AEROSPIKE_LOCAL_PKG:-0}" = "1" ]; then \
      cp /tmp/server_x86_64.rpm server.rpm; \
      [ -f /tmp/server_x86_64.rpm.sha256 ] && { \
        hash=$(awk '{print $1}' /tmp/server_x86_64.rpm.sha256); \
        echo "${hash}  server.rpm" | sha256sum -c -; \
      }; \
    else \
      pkg_link="${AEROSPIKE_X86_64_LINK}"; \
      sha256="${AEROSPIKE_SHA_X86_64}"; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.rpm; then \
        sleep 5; \
        curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.rpm; \
      fi; \
      [ -n "${sha256}" ] && echo "${sha256} server.rpm" | sha256sum -c -; \
    fi; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      microdnf install -y --setopt=install_weak_deps=0 openldap; \
    fi; \
    rpm -i --excludedocs server.rpm; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    mkdir -p /var/{log,run}/aerospike; \
  }; \
  { \
    rm -f server.rpm; \
    if ! microdnf clean all; then true; fi; \
    rm -rf /var/cache/yum /var/cache/dnf; \
  }; \
  echo "done";

RUNBLOCK
        elif [ "${single_arch}" = "arm64" ]; then
            cat <<'RUNBLOCK'
# Install Aerospike Server (arm64)
# hadolint ignore=DL3041
RUN \
  _retry() { local _i; for _i in 1 2 3 4 5; do if "$@"; then return 0; fi; sleep $((_i*5)); done; "$@"; }; \
  { \
    _retry microdnf install -y --setopt=install_weak_deps=0 ca-certificates shadow-utils; \
  }; \
  { \
    if ! command -v curl >/dev/null 2>&1; then \
      if ! _retry microdnf install -y curl-minimal; then \
        _retry microdnf install -y curl; \
      fi; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64" -o /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64" -o /usr/bin/as-tini-static; \
    fi; \
    echo "1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    if [ "${AEROSPIKE_LOCAL_PKG:-0}" = "1" ]; then \
      cp /tmp/server_aarch64.rpm server.rpm; \
      [ -f /tmp/server_aarch64.rpm.sha256 ] && { \
        hash=$(awk '{print $1}' /tmp/server_aarch64.rpm.sha256); \
        echo "${hash}  server.rpm" | sha256sum -c -; \
      }; \
    else \
      pkg_link="${AEROSPIKE_AARCH64_LINK}"; \
      sha256="${AEROSPIKE_SHA_AARCH64}"; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.rpm; then \
        sleep 5; \
        curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.rpm; \
      fi; \
      [ -n "${sha256}" ] && echo "${sha256} server.rpm" | sha256sum -c -; \
    fi; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      _retry microdnf install -y --setopt=install_weak_deps=0 openldap; \
    fi; \
    if ! rpm -i --excludedocs server.rpm; then \
      sleep 3; \
      rpm -i --force --excludedocs server.rpm; \
    fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    mkdir -p /var/{log,run}/aerospike; \
  }; \
  { \
    rm -f server.rpm; \
    if ! microdnf clean all; then true; fi; \
    rm -rf /var/cache/yum /var/cache/dnf; \
  }; \
  echo "done";

RUNBLOCK
        else
            cat <<'RUNBLOCK'
# Install Aerospike Server
# hadolint ignore=DL3041
RUN \
  _retry() { local _i; for _i in 1 2 3 4 5; do if "$@"; then return 0; fi; sleep $((_i*5)); done; "$@"; }; \
  { \
    _retry microdnf install -y --setopt=install_weak_deps=0 ca-certificates shadow-utils; \
  }; \
  { \
    if ! command -v curl >/dev/null 2>&1; then \
      if ! _retry microdnf install -y curl-minimal; then \
        _retry microdnf install -y curl; \
      fi; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    ARCH="$(uname -m)"; \
    if [ "${ARCH}" = "x86_64" ]; then \
      sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
      suffix=""; \
    elif [ "${ARCH}" = "aarch64" ]; then \
      sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b; \
      suffix="-arm64"; \
    else \
      echo "Unsupported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" -o /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" -o /usr/bin/as-tini-static; \
    fi; \
    echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    ARCH="$(uname -m)"; \
    if [ "${AEROSPIKE_LOCAL_PKG:-0}" = "1" ]; then \
      if [ "${ARCH}" = "x86_64" ]; then \
        cp /tmp/server_x86_64.rpm server.rpm; \
        [ -f /tmp/server_x86_64.rpm.sha256 ] && { \
          hash=$(awk '{print $1}' /tmp/server_x86_64.rpm.sha256); \
          echo "${hash}  server.rpm" | sha256sum -c -; \
        }; \
      else \
        cp /tmp/server_aarch64.rpm server.rpm; \
        [ -f /tmp/server_aarch64.rpm.sha256 ] && { \
          hash=$(awk '{print $1}' /tmp/server_aarch64.rpm.sha256); \
          echo "${hash}  server.rpm" | sha256sum -c -; \
        }; \
      fi; \
    else \
      if [ "${ARCH}" = "x86_64" ]; then \
        pkg_link="${AEROSPIKE_X86_64_LINK}"; \
        sha256="${AEROSPIKE_SHA_X86_64}"; \
      else \
        pkg_link="${AEROSPIKE_AARCH64_LINK}"; \
        sha256="${AEROSPIKE_SHA_AARCH64}"; \
      fi; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.rpm; then \
        sleep 5; \
        curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o server.rpm; \
      fi; \
      [ -n "${sha256}" ] && echo "${sha256} server.rpm" | sha256sum -c -; \
    fi; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      _retry microdnf install -y --setopt=install_weak_deps=0 openldap; \
    fi; \
    if [ "${ARCH}" = "aarch64" ]; then \
      if ! rpm -i --excludedocs server.rpm; then \
        sleep 3; \
        rpm -i --force --excludedocs server.rpm; \
      fi; \
    else \
      rpm -i --excludedocs server.rpm; \
    fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    mkdir -p /var/{log,run}/aerospike; \
  }; \
  { \
    rm -f server.rpm; \
    if ! microdnf clean all; then true; fi; \
    rm -rf /var/cache/yum /var/cache/dnf; \
  }; \
  echo "done";

RUNBLOCK
        fi
    fi
}

# generate_dockerfile lineage distro edition version tools_version
function generate_dockerfile() {
    local lineage=$1 distro=$2 edition=$3 version=$4 tools_version=$5
    local target="releases/${lineage}/${edition}/${distro}"

    log_info "  Generating ${edition}/${distro}"

    local artifact_distro pkg_type base_image
    artifact_distro=$(support_distro_to_artifact_name "${distro}")
    pkg_type=$(support_distro_to_pkg_type "${distro}")
    base_image=$(support_distro_to_base "${distro}")

    local x86_link="" x86_sha="" arm_link="" arm_sha=""
    local pkg_format="tgz"

    # Derive single_arch when exactly one arch is filtered (enables simplified Dockerfile generation).
    local single_arch=""
    if [ ${#ARCH_FILTERS[@]} -eq 1 ]; then
        single_arch="${ARCH_FILTERS[0]}"
        [ "${single_arch}" = "x86_64" ] && single_arch="amd64"
        [ "${single_arch}" = "aarch64" ] && single_arch="arm64"
    fi

    # When no tools version: skip tgz, go straight to native .rpm/.deb (server only)
    if [ -n "${tools_version}" ]; then
        x86_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
        x86_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
        arm_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
        arm_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
    fi

    # When -u is a local dir: always try local .rpm/.deb first (tgz/sha may exist and would skip local otherwise)
    local use_local_pkg=""
    if is_local_artifacts_dir; then
        local local_base="${ARTIFACTS_DOMAIN}"
        # Resolve relative -u to script dir so ./artifacts always means repo/artifacts
        [[ "${local_base}" != /* ]] && [[ "${local_base}" != http* ]] && local_base="${SCRIPT_DIR}/${local_base}"
        [ -d "${local_base}" ] && local_base=$(cd "${local_base}" && pwd)
        local local_x86 local_arm
        local_x86=$(find_local_server_package "${local_base}" "${artifact_distro}" "${edition}" "${version}" "x86_64" "${pkg_type}")
        local_arm=$(find_local_server_package "${local_base}" "${artifact_distro}" "${edition}" "${version}" "aarch64" "${pkg_type}")
        if [ -n "${local_x86}" ] || [ -n "${local_arm}" ]; then
            pkg_format="${pkg_type}"
            [ -n "${local_x86}" ] && x86_link="${local_x86}"
            [ -n "${local_arm}" ] && arm_link="${local_arm}"
            use_local_pkg="1"
        fi
    fi

    # If no local packages (or not local dir), use tgz or remote native rpm/deb
    if [ -z "${use_local_pkg}" ] && [ -z "${x86_sha}" ]; then
        if ! is_local_artifacts_dir; then
            x86_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64" "${pkg_type}")
            x86_sha=$(fetch_sha_for_link "${x86_link}")
            if [ -n "${x86_link}" ]; then
                pkg_format="${pkg_type}"
                arm_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64" "${pkg_type}")
                arm_sha=$(fetch_sha_for_link "${arm_link}")
            fi
        fi
    fi

    # When building single-arch, clear unused arch to keep the generated Dockerfile simple.
    if [ "${single_arch}" = "amd64" ]; then
        arm_link=""
        arm_sha=""
    fi
    if [ "${single_arch}" = "arm64" ]; then
        x86_link=""
        x86_sha=""
    fi

    # Skip only when we have no package (no tgz sha, no native link, and no local package)
    if [ -z "${x86_sha}" ] && [ -z "${use_local_pkg}" ] && { [ "${pkg_format}" = "tgz" ] || [ -z "${x86_link}" ]; }; then
        log_warn "    Skipping - package not available (tried tgz and ${pkg_type})"
        return 1
    fi
    if [ -z "${x86_sha}" ] && [ -n "${use_local_pkg}" ] && [ -z "${x86_link}" ] && [ -z "${arm_link}" ]; then
        log_warn "    Skipping - no local package found"
        return 1
    fi

    [ "${pkg_format}" != "tgz" ] && log_info "    Using native ${pkg_format} (tgz not found)"
    [ -n "${use_local_pkg}" ] && log_info "    Using local packages from ${ARTIFACTS_DOMAIN}"

    mkdir -p "${target}"
    cp template/0/entrypoint.sh "${target}/"
    chmod +x "${target}/entrypoint.sh"
    cp template/7/aerospike.template.conf "${target}/"
    if [ "${edition}" = "enterprise" ] || [ "${edition}" = "federal" ]; then
        cp config/eval_features.conf "${target}/features.conf" || {
            log_error "    Missing required feature key source: config/eval_features.conf"
            return 1
        }
    fi

    # When -u is a local dir: ensure .sha256 exist (run shasum-artifacts.sh if any missing), then copy packages and .sha256
    local dockerfile_copy_local=""
    local copy_files=()
    if [ -n "${use_local_pkg}" ] && [ "${pkg_format}" != "tgz" ]; then
        local need_sha=false
        [ -n "${x86_link}" ] && [ ! -f "${x86_link}.sha256" ] && need_sha=true
        [ -n "${arm_link}" ] && [ ! -f "${arm_link}.sha256" ] && need_sha=true
        if [ "${need_sha}" = true ]; then
            local local_base="${ARTIFACTS_DOMAIN}"
            [[ "${local_base}" != /* ]] && [[ "${local_base}" != http* ]] && local_base="${SCRIPT_DIR}/${local_base}"
            [ -d "${local_base}" ] && local_base=$(cd "${local_base}" && pwd)
            if [ -d "${local_base}" ]; then
                log_info "    Creating missing .sha256 in ${local_base} (shasum-artifacts.sh)"
                "${SCRIPT_DIR}/scripts/shasum-artifacts.sh" "${local_base}" >/dev/null 2>&1 || true
            fi
        fi
        if [ "${pkg_type}" = "rpm" ]; then
            if [ -n "${x86_link}" ]; then
                cp "${x86_link}" "${target}/server_x86_64.rpm" && copy_files+=(server_x86_64.rpm)
                [ -f "${x86_link}.sha256" ] && cp "${x86_link}.sha256" "${target}/server_x86_64.rpm.sha256" && copy_files+=(server_x86_64.rpm.sha256) && x86_sha=$(awk '{print $1}' "${x86_link}.sha256")
            fi
            if [ -n "${arm_link}" ]; then
                cp "${arm_link}" "${target}/server_aarch64.rpm" && copy_files+=(server_aarch64.rpm)
                [ -f "${arm_link}.sha256" ] && cp "${arm_link}.sha256" "${target}/server_aarch64.rpm.sha256" && copy_files+=(server_aarch64.rpm.sha256) && arm_sha=$(awk '{print $1}' "${arm_link}.sha256")
            fi
        else
            if [ -n "${x86_link}" ]; then
                cp "${x86_link}" "${target}/server_amd64.deb" && copy_files+=(server_amd64.deb)
                [ -f "${x86_link}.sha256" ] && cp "${x86_link}.sha256" "${target}/server_amd64.deb.sha256" && copy_files+=(server_amd64.deb.sha256) && x86_sha=$(awk '{print $1}' "${x86_link}.sha256")
            fi
            if [ -n "${arm_link}" ]; then
                cp "${arm_link}" "${target}/server_arm64.deb" && copy_files+=(server_arm64.deb)
                [ -f "${arm_link}.sha256" ] && cp "${arm_link}.sha256" "${target}/server_arm64.deb.sha256" && copy_files+=(server_arm64.deb.sha256) && arm_sha=$(awk '{print $1}' "${arm_link}.sha256")
            fi
        fi
        [ ${#copy_files[@]} -gt 0 ] && dockerfile_copy_local="COPY ${copy_files[*]} /tmp/"
    fi

    # AEROSPIKE_COMPAT_LIBS: install legacy libssl1.1/libcurl4 from older Ubuntu repos.
    # Only 7.2 binaries still link against OpenSSL 1.1 on ubuntu24.04.
    # 8.0+ must be built against OpenSSL 3 (libssl1.1 carries high CVEs).
    # 7.1 runs on ubuntu22.04 which has libssl1.1 natively.
    # Operational note: focal/jammy archive layout or package renames can break the
    # compat path; update repo lines and package names when builds fail at apt/dpkg.
    local needs_compat_libs="0"
    if [[ "${distro}" == ubuntu24.04 ]] && [[ "${lineage}" == "7.2" ]]; then
        needs_compat_libs="1"
    fi

    local dockerfile_extra_args=""
    [ -n "${use_local_pkg}" ] && dockerfile_extra_args="ARG AEROSPIKE_LOCAL_PKG=\"1\""
    local dockerfile_x86_args=""
    if [ "${single_arch}" != "arm64" ]; then
        dockerfile_x86_args="ARG AEROSPIKE_X86_64_LINK=\"${x86_link}\"
ARG AEROSPIKE_SHA_X86_64=\"${x86_sha}\""
    fi
    local dockerfile_aarch64_args=""
    if [ "${single_arch}" != "amd64" ]; then
        dockerfile_aarch64_args="ARG AEROSPIKE_AARCH64_LINK=\"${arm_link}\"
ARG AEROSPIKE_SHA_AARCH64=\"${arm_sha}\""
    fi
    local dockerfile_features_copy=""
    if [ "${edition}" = "enterprise" ] || [ "${edition}" = "federal" ]; then
        dockerfile_features_copy="COPY features.conf /etc/aerospike/features.conf"
    fi

    local base_name_label="${base_image}"
    [[ "${base_image}" == ubuntu:* ]] && base_name_label="docker.io/library/${base_image}"

    local image_license="Apache-2.0"
    [ "${edition}" = "enterprise" ] && image_license="Proprietary"
    [ "${edition}" = "federal" ] && image_license="Proprietary"

    {
        # Header: FROM, LABEL, ARG (needs shell variable expansion)
        cat <<HEADER
#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM ${base_image}

LABEL org.opencontainers.image.title="Aerospike ${edition^} Server" \\
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \\
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \\
      org.opencontainers.image.base.name="${base_name_label}" \\
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \\
      org.opencontainers.image.licenses="${image_license}" \\
      org.opencontainers.image.vendor="Aerospike" \\
      org.opencontainers.image.version="${version}" \\
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="${edition}"

ENV AEROSPIKE_LINUX_BASE="${base_image}"
${dockerfile_x86_args}
${dockerfile_aarch64_args}
ARG AEROSPIKE_COMPAT_LIBS="${needs_compat_libs}"
${dockerfile_extra_args}

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

HEADER

        # Optional COPY for local packages (before RUN)
        if [ -n "${dockerfile_copy_local}" ]; then
            echo "${dockerfile_copy_local}"
            echo ""
        fi

        # Inline RUN block (literal, no shell expansion via quoted heredocs)
        if [ "${pkg_type}" = "deb" ]; then
            _append_run_deb "${pkg_format}" "${single_arch}"
        else
            _append_run_rpm "${pkg_format}" "${single_arch}"
        fi

        # Footer: COPY, EXPOSE, ENTRYPOINT, CMD (literal)
        cat <<FOOTER
# Add the Aerospike configuration specific to this dockerfile
COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
${dockerfile_features_copy}

# Mount the Aerospike data directory
# VOLUME ["/opt/aerospike/data"]
# Mount the Aerospike config directory
# VOLUME ["/etc/aerospike/"]

# Expose Aerospike ports
#
#   3000 – service port, for client connections
#   3001 – fabric port, for cluster communication
#   3002 – mesh port, for cluster heartbeat
#
EXPOSE 3000 3001 3002

COPY entrypoint.sh /entrypoint.sh

# Tini init set to restart ASD on SIGUSR1 and terminate ASD on SIGTERM
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Execute the run script in foreground mode
CMD ["asd"]
FOOTER
    } | sed 's/[[:space:]]*$//' | cat -s >"${target}/Dockerfile"

    # Ensure file ends with newline (Docker Hub / validators expect it)
    [ -n "$(tail -c1 "${target}/Dockerfile" 2>/dev/null)" ] && echo >>"${target}/Dockerfile"
}

function generate_dockerfiles() {
    local version_or_lineage=$1

    log_info "=== Generating Dockerfiles ==="
    log_info "Fetching versions from ${ARTIFACTS_DOMAIN}..."
    [ ${#EDITION_FILTERS[@]} -gt 0 ] && log_info "  Editions: ${EDITION_FILTERS[*]}"
    [ ${#DISTRO_FILTERS[@]} -gt 0 ] && log_info "  Distros: ${DISTRO_FILTERS[*]}"
    echo ""

    declare -A VERSION_MAP TOOLS_MAP
    declare -ag LINEAGES_TO_BUILD=()

    if [[ "${version_or_lineage}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        local version="${version_or_lineage}"
        local lineage tools_version
        lineage=$(get_lineage_from_version "${version}")
        tools_version=$(find_tools_version "${version}")
        VERSION_MAP["${lineage}"]="${version}"
        TOOLS_MAP["${lineage}"]="${tools_version:-}"
        LINEAGES_TO_BUILD=("${lineage}")
        if [ -z "${tools_version}" ]; then
            log_warn "${version} -> tools NOT FOUND (will try native .rpm/.deb only, no tools)"
        else
            log_info "  ${version} (lineage: ${lineage}, tools: ${tools_version})"
        fi
    elif [[ "${version_or_lineage}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        local lineage="${version_or_lineage}"
        local version tools_version
        version=$(find_latest_version_for_lineage "${lineage}")
        [ -z "${version}" ] && {
            log_warn "${lineage} -> NOT FOUND"
            exit 1
        }
        tools_version=$(find_tools_version "${version}")
        VERSION_MAP["${lineage}"]="${version}"
        TOOLS_MAP["${lineage}"]="${tools_version:-}"
        LINEAGES_TO_BUILD=("${lineage}")
        if [ -z "${tools_version}" ]; then
            log_warn "${lineage} -> ${version} (tools NOT FOUND; will try native .rpm/.deb only, no tools)"
        else
            log_info "  ${lineage} -> ${version} (tools: ${tools_version})"
        fi
    else
        for lineage in $(support_releases); do
            local version tools_version
            version=$(find_latest_version_for_lineage "${lineage}")
            [ -z "${version}" ] && {
                log_warn "${lineage} -> NOT FOUND"
                continue
            }
            tools_version=$(find_tools_version "${version}")
            VERSION_MAP["${lineage}"]="${version}"
            TOOLS_MAP["${lineage}"]="${tools_version:-}"
            LINEAGES_TO_BUILD+=("${lineage}")
            if [ -z "${tools_version}" ]; then
                log_warn "${lineage} -> ${version} (tools NOT FOUND; will try native .rpm/.deb only)"
            else
                log_info "  ${lineage} -> ${version} (tools: ${tools_version})"
            fi
        done
    fi

    if [ ${#LINEAGES_TO_BUILD[@]} -eq 0 ]; then
        log_warn "Nothing to build (no version/lineage had packages available). Use -u for a custom server with native rpm/deb."
        exit 1
    fi

    echo ""
    rm -rf releases/

    for lineage in "${LINEAGES_TO_BUILD[@]}"; do
        local version="${VERSION_MAP[${lineage}]:-}"
        local tools_version="${TOOLS_MAP[${lineage}]:-}"
        [ -z "${version}" ] && continue

        local distros_lineage
        distros_lineage=$(support_distros_matching "${lineage}" "${DISTRO_FILTERS[*]:-}")
        log_info "Processing ${lineage} (${version})"

        for edition in $(support_editions); do
            if [ ${#EDITION_FILTERS[@]} -gt 0 ]; then
                local match=false
                for ef in "${EDITION_FILTERS[@]}"; do
                    [ "${ef}" = "${edition}" ] && {
                        match=true
                        break
                    }
                done
                [ "${match}" = false ] && continue
            fi

            for distro in ${distros_lineage}; do
                generate_dockerfile "${lineage}" "${distro}" "${edition}" "${version}" "${tools_version}" || true
            done
        done
    done

    # Export for bake generation
    declare -gA G_VERSION_MAP
    for key in "${!VERSION_MAP[@]}"; do
        G_VERSION_MAP["${key}"]="${VERSION_MAP[${key}]}"
    done
}

#------------------------------------------------------------------------------
# Generate bake file and build
#------------------------------------------------------------------------------
function generate_bake() {
    local build_ts="${1:-}"
    [ -z "${build_ts}" ] && build_ts=$(date -u +%Y%m%d%H%M%S 2>/dev/null || date +%Y%m%d%H%M%S)
    local test_targets="" push_targets=""
    local test_group="" push_group=""

    for lineage in "${LINEAGES_TO_BUILD[@]}"; do
        local version="${G_VERSION_MAP[${lineage}]}"
        local distros_building
        distros_building=$(support_distros_matching "${lineage}" "${DISTRO_FILTERS[*]:-}")
        local omit_distro_in_tag=0
        local num_distros
        num_distros=$(echo "${distros_building}" | wc -w)
        # Single distro -> tag without distro suffix (e.g. 7.1.0.21 instead of 7.1.0.21-ubuntu22.04)
        [ "${num_distros}" -eq 1 ] && omit_distro_in_tag=1

        for edition in $(support_editions); do
            if [ ${#EDITION_FILTERS[@]} -gt 0 ]; then
                local match=false
                for ef in "${EDITION_FILTERS[@]}"; do
                    [ "${ef}" = "${edition}" ] && {
                        match=true
                        break
                    }
                done
                [ "${match}" = false ] && continue
            fi

            for distro in ${distros_building}; do
                local ctx="./releases/${lineage}/${edition}/${distro}"
                [ ! -d "${ctx}" ] && continue

                local tag_base platforms
                tag_base="${lineage//./-}_${edition}_${distro//./-}"
                platforms=$(support_platforms_matching "${edition}" "${ARCH_FILTERS[*]:-}")
                [ -z "${platforms}" ] && continue
                local image_name="aerospike-server"
                [ "${edition}" != "community" ] && image_name+="-${edition}"
                local test_product="${REGISTRY_PREFIXES[0]}/${image_name}"

                for plat in ${platforms}; do
                    local arch=${plat#*/}
                    local test_tag
                    if [ "${omit_distro_in_tag}" -eq 1 ]; then
                        test_tag="${test_product}:${version}-${arch}"
                    else
                        test_tag="${test_product}:${version}-${distro}-${arch}"
                    fi
                    test_group+="\"${tag_base}_${arch}\", "
                    test_targets+="target \"${tag_base}_${arch}\" {
    tags=[\"${test_tag}\"]
    platforms=[\"${plat}\"]
    context=\"${ctx}\"
}
"
                done

                local push_tags=""
                for reg in "${REGISTRY_PREFIXES[@]}"; do
                    local product="${reg}/${image_name}"
                    [ -n "${push_tags}" ] && push_tags+=", "
                    if [ "${omit_distro_in_tag}" -eq 1 ]; then
                        push_tags+="\"${product}:${lineage}\", \"${product}:${version}\", \"${product}:${version}-${build_ts}\""
                    else
                        push_tags+="\"${product}:${lineage}-${distro}\", \"${product}:${version}-${distro}\", \"${product}:${version}-${distro}-${build_ts}\""
                    fi
                done
                push_group+="\"${tag_base}\", "
                push_targets+="target \"${tag_base}\" {
    tags=[${push_tags}]
    platforms=[\"${platforms// /\", \"}\"]
    context=\"${ctx}\"
}
"
            done
        done
    done

    cat >"${BAKE_FILE}" <<EOF
# Auto-generated bake file
group "test" { targets=[${test_group%,*}] }
group "push" { targets=[${push_group%,*}] }

${test_targets}
${push_targets}
EOF
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
function main() {
    local mode="" custom_url="" version_or_lineage=""
    local generate_only=false
    local -a bake_opts=()
    local build_timestamp=""
    declare -ga REGISTRY_PREFIXES=()

    # Arrays for multiple values
    declare -ga EDITION_FILTERS=()
    declare -ga DISTRO_FILTERS=()
    declare -ga ARCH_FILTERS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -t)
            mode="test"
            shift
            ;;
        -p)
            mode="push"
            shift
            ;;
        -r | --registry)
            REGISTRY_PREFIXES+=("$2")
            shift 2
            ;;
        -g | --generate)
            generate_only=true
            shift
            ;;
        -u | --url)
            custom_url="$2"
            shift 2
            ;;
        -e | --edition)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                EDITION_FILTERS+=("$1")
                shift
            done
            ;;
        -d | --distro)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                DISTRO_FILTERS+=("$1")
                shift
            done
            ;;
        -a | --arch)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                ARCH_FILTERS+=("$1")
                shift
            done
            ;;
        -T | --timestamp)
            build_timestamp="$2"
            shift 2
            ;;
        --no-cache)
            bake_opts+=(--no-cache)
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            log_warn "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            version_or_lineage="$1"
            shift
            ;;
        esac
    done

    if [ "${generate_only}" = false ] && [ -z "${mode}" ]; then
        log_warn "Mode (-t, -p, or -g) required"
        usage
        exit 1
    fi

    [ ${#REGISTRY_PREFIXES[@]} -eq 0 ] && REGISTRY_PREFIXES=("aerospike")
    [ -n "${custom_url}" ] && export ARTIFACTS_DOMAIN="${custom_url}"

    # Step 1: Generate Dockerfiles
    generate_dockerfiles "${version_or_lineage}"

    echo ""
    log_info "Dockerfiles generated in releases/"

    # Step 2: Build (unless generate-only)
    if [ "${generate_only}" = true ]; then
        exit 0
    fi

    echo ""
    log_info "=== Building Images ==="

    generate_bake "${build_timestamp}"

    case "${mode}" in
    test)
        log_info "Building for local testing..."
        docker buildx bake -f "${BAKE_FILE}" test --progress plain --load "${bake_opts[@]}"
        ;;
    push)
        log_info "Building and pushing to registry/registries (${REGISTRY_PREFIXES[*]})..."
        docker buildx bake -f "${BAKE_FILE}" push --progress plain --push "${bake_opts[@]}"
        ;;
    esac

    echo ""
    log_info "Done!"
}

main "$@"
