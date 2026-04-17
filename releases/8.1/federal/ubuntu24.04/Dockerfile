# syntax=docker/dockerfile:1
#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Aerospike Federal Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.1.2.0" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="federal"

ENV AEROSPIKE_LINUX_BASE="ubuntu:24.04"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-federal/8.1.2.0/aerospike-server-federal_8.1.2.0_tools-13.0.0_ubuntu24.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="266911508ba6289d5a286ed16c41cc53d234e0f4f56bff9b5408bc6dfee9693b"
ARG AEROSPIKE_AARCH64_LINK=""
ARG AEROSPIKE_SHA_AARCH64=""
ARG AEROSPIKE_COMPAT_LIBS="0"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install Aerospike Server and Tools
# hadolint ignore=DL3003,DL3008,DL3041,SC2015
RUN bash <<'AEROSPIKE_INSTALL'
#!/usr/bin/env bash
# Ubuntu/Debian: install Aerospike server + tools.
# Single source of truth for all DEB-based Docker images.
# Executed from the Dockerfile RUN heredoc (BuildKit); not copied as a separate layer file.
#
# Expected ARG/ENV from Dockerfile:
#   AEROSPIKE_EDITION        community|enterprise|federal
#   AEROSPIKE_X86_64_LINK    download URL (amd64, tgz or native deb)
#   AEROSPIKE_SHA_X86_64     SHA256
#   AEROSPIKE_AARCH64_LINK   download URL (arm64, tgz or native deb)
#   AEROSPIKE_SHA_AARCH64    SHA256
#   AEROSPIKE_COMPAT_LIBS    0|1 (legacy libssl1.1/libcurl4 for 7.2 on ubuntu24.04)
#   AEROSPIKE_LOCAL_PKG      0|1 (when using -u local dir, packages pre-copied to /tmp)
#
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Install LDAP dependencies for enterprise/federal editions.
# Ubuntu 24.04 no longer ships libldap; we fallback to Focal/Jammy repos.
function _install_ldap_deps() {
    if apt-cache show libldap-2.5-0 >/dev/null 2>&1; then
        if ! apt-get install -y --no-install-recommends libldap-2.5-0; then
            echo "Note: libldap-2.5-0 available but not installable"
        fi
    fi
    if apt-cache show libldap-2.4-2 >/dev/null 2>&1; then
        if ! apt-get install -y --no-install-recommends libldap-2.4-2; then
            echo "Note: libldap-2.4-2 available but not installable"
        fi
    fi
    if ! dpkg --configure -a; then true; fi

    if ! { ls /usr/lib/*/liblber-2.4.so.2 >/dev/null 2>&1 ||
        ls /usr/lib/*/liblber-2.5.so.0 >/dev/null 2>&1; }; then
        if [ "$(dpkg --print-architecture)" = "amd64" ]; then
            ldap_repo="http://archive.ubuntu.com/ubuntu"
        else
            ldap_repo="http://ports.ubuntu.com/ubuntu-ports"
        fi
        echo "deb [trusted=yes] ${ldap_repo} focal main" >/etc/apt/sources.list.d/focal-ldap.list
        echo "deb [trusted=yes] ${ldap_repo} jammy main" >/etc/apt/sources.list.d/jammy-ldap.list
        apt-get update -y
        if apt-cache show libldap-2.5-0 >/dev/null 2>&1; then
            if ! apt-get install -y --no-install-recommends libldap-2.5-0; then
                echo "Note: libldap-2.5-0 available but not installable from fallback repos"
            fi
        fi
        if apt-cache show libldap-2.4-2 >/dev/null 2>&1; then
            if ! apt-get install -y --no-install-recommends libldap-2.4-2; then
                echo "Note: libldap-2.4-2 available but not installable from fallback repos"
            fi
        fi
        if ! dpkg --configure -a; then true; fi
        rm -f /etc/apt/sources.list.d/focal-ldap.list /etc/apt/sources.list.d/jammy-ldap.list
    fi

    { ls /usr/lib/*/liblber-2.4.so.2 >/dev/null 2>&1 ||
        ls /usr/lib/*/liblber-2.5.so.0 >/dev/null 2>&1; } ||
        {
            echo "ERROR: liblber not found - libldap install failed" >&2
            exit 1
        }
}

# Compat libs for tgz mode (simple: just install from current repos)
function _install_compat_libs_tgz() {
    curl_pkg="libcurl4"
    apt-cache show libcurl4t64 >/dev/null 2>&1 && curl_pkg="libcurl4t64"
    for cpkg in libssl1.1 "${curl_pkg}"; do
        if apt-cache show "${cpkg}" >/dev/null 2>&1; then
            if ! apt-get install -y --no-install-recommends "${cpkg}"; then
                echo "Note: ${cpkg} available but not installable"
            fi
        fi
    done
    if ! dpkg --configure -a; then true; fi
}

# Compat libs for native deb mode (adds focal/jammy repos for older packages)
function _install_compat_libs_native() {
    . /etc/os-release
    if [ "${ID:-}" = "ubuntu" ]; then
        if [ "$(dpkg --print-architecture)" = "amd64" ]; then
            repo_url="http://archive.ubuntu.com/ubuntu"
        else
            repo_url="http://ports.ubuntu.com/ubuntu-ports"
        fi
        echo "deb [trusted=yes] ${repo_url} focal main" >/etc/apt/sources.list.d/focal-compat.list
        [ "${VERSION_ID}" != "22.04" ] &&
            echo "deb [trusted=yes] ${repo_url} jammy main" >/etc/apt/sources.list.d/jammy-compat.list
        apt-get update -y
        if ! dpkg --configure -a; then true; fi
        curl_pkg="libcurl4"
        apt-cache show libcurl4t64 >/dev/null 2>&1 && curl_pkg="libcurl4t64"
        for cpkg in libssl1.1 "${curl_pkg}" libldap-2.4-2 libldap-2.5-0; do
            if apt-cache show "${cpkg}" >/dev/null 2>&1; then
                if ! apt-get install -y --no-install-recommends "${cpkg}"; then
                    echo "Note: ${cpkg} available but not installable"
                fi
            fi
        done
        if ! dpkg --configure -a; then true; fi
        if ! ldconfig; then true; fi
        if ! ldconfig -p 2>/dev/null | grep -q libcrypto.so.1.1; then
            rm -f /var/cache/apt/archives/*.deb 2>/dev/null
            curl_pkg="libcurl4"
            apt-cache show libcurl4t64 >/dev/null 2>&1 && curl_pkg="libcurl4t64"
            for cpkg in libssl1.1 "${curl_pkg}" libldap-2.4-2 libldap-2.5-0; do
                if apt-cache show "${cpkg}" >/dev/null 2>&1; then
                    if ! apt-get install -y --no-install-recommends --download-only "${cpkg}" 2>/dev/null; then true; fi
                fi
            done
            if ls /var/cache/apt/archives/*.deb >/dev/null 2>&1; then
                if ! dpkg -i /var/cache/apt/archives/*.deb; then
                    echo "Note: some compat lib debs could not be installed"
                fi
            fi
            if ! dpkg --configure -a; then true; fi
        fi
        rm -f /etc/apt/sources.list.d/focal-compat.list /etc/apt/sources.list.d/jammy-compat.list
    fi
}

# Install tools from extracted tgz (tools .deb -> ar -> tar -> move binaries)
function _install_tools_from_tgz() {
    ar -x aerospike/aerospike-tools*.deb --output aerospike/pkg
    tar xf aerospike/pkg/data.tar.xz -C aerospike/pkg/

    find aerospike/pkg/opt/aerospike/bin/ -exec chown root:root {} +
    mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike
    if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then
        mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/
    else
        mkdir -p /usr/lib/asadm
        mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/
    fi
    ln -snf /usr/lib/asadm/asadm /usr/bin/asadm
    if [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ]; then
        mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/
    fi
    ln -snf /usr/lib/asadm/asinfo /usr/bin/asinfo
}

# ---------------------------------------------------------------------------
# Main install logic
# ---------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive
ARCH="$(dpkg --print-architecture)"

# Install build dependencies
apt-get update -y
if [ "${ARCH}" = "arm64" ]; then
    if ! apt-get install -y --no-install-recommends \
        binutils xz-utils ca-certificates curl procps; then
        if ! dpkg --configure -a; then true; fi
        sleep 2
        if ! dpkg --configure -a; then true; fi
    fi
else
    apt-get install -y --no-install-recommends \
        binutils xz-utils ca-certificates curl procps
fi
command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl not found" >&2
    exit 1
}

# Download and verify tini
if [ "${ARCH}" = "amd64" ]; then
    tini_sha=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940
    tini_suffix=""
else
    tini_sha=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b
    tini_suffix="-arm64"
fi
if ! curl -fsSL --retry 3 --retry-delay 3 \
    "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${tini_suffix}" \
    -o /usr/bin/as-tini-static; then
    sleep 5
    curl -fsSL --retry 3 --retry-delay 3 \
        "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${tini_suffix}" \
        -o /usr/bin/as-tini-static
fi
echo "${tini_sha} /usr/bin/as-tini-static" | sha256sum -c -
chmod +x /usr/bin/as-tini-static

# Select arch-specific package link and SHA
if [ "${ARCH}" = "amd64" ]; then
    pkg_link="${AEROSPIKE_X86_64_LINK:-}"
    sha256="${AEROSPIKE_SHA_X86_64:-}"
else
    pkg_link="${AEROSPIKE_AARCH64_LINK:-}"
    sha256="${AEROSPIKE_SHA_AARCH64:-}"
fi

# --- Install: local native .deb (AEROSPIKE_LOCAL_PKG=1) ---
if [ "${AEROSPIKE_LOCAL_PKG:-0}" = "1" ]; then
    if [ "${ARCH}" = "amd64" ]; then
        cp /tmp/server_amd64.deb server.deb
        if [ -f /tmp/server_amd64.deb.sha256 ]; then
            pkg_hash=$(awk '{print $1}' /tmp/server_amd64.deb.sha256)
            echo "${pkg_hash}  server.deb" | sha256sum -c -
        fi
    else
        cp /tmp/server_arm64.deb server.deb
        if [ -f /tmp/server_arm64.deb.sha256 ]; then
            pkg_hash=$(awk '{print $1}' /tmp/server_arm64.deb.sha256)
            echo "${pkg_hash}  server.deb" | sha256sum -c -
        fi
    fi

    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
        _install_ldap_deps
    fi
    if [ "${AEROSPIKE_COMPAT_LIBS:-0}" = "1" ]; then
        _install_compat_libs_native
    fi

    if [ "${ARCH}" = "arm64" ]; then
        if ! dpkg -i server.deb; then
            if ! dpkg --configure -a; then true; fi
            sleep 2
        fi
        if ! dpkg --configure -a; then true; fi
    else
        dpkg -i server.deb
    fi
    command -v asd >/dev/null 2>&1 || {
        echo "ERROR: asd not installed" >&2
        exit 1
    }
    mkdir -p /var/{log,run}/aerospike

    rm -f server.deb
    if ! dpkg --purge curl; then
        echo "Note: keeping curl (has reverse dependencies)"
    fi
    if ! apt-get autoremove -y; then true; fi
    rm -rf /var/lib/apt/lists/*

# --- Install: tgz bundle (default) ---
else
    mkdir -p aerospike/pkg
    if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o aerospike-server.tgz; then
        sleep 5
        if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o aerospike-server.tgz; then
            echo "Could not fetch pkg - ${pkg_link}" >&2
            exit 1
        fi
    fi
    echo "${sha256} aerospike-server.tgz" | sha256sum -c -
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike
    rm aerospike-server.tgz
    mkdir -p /var/{log,run}/aerospike /etc/aerospike /licenses
    cp aerospike/LICENSE /licenses
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
        if [ -f aerospike/features.conf ]; then
            cp aerospike/features.conf /etc/aerospike/features.conf
        elif [ -f aerospike/etc/aerospike/features.conf ]; then
            cp aerospike/etc/aerospike/features.conf /etc/aerospike/features.conf
        fi
    fi

    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
        _install_ldap_deps
    fi
    if [ "${AEROSPIKE_COMPAT_LIBS:-0}" = "1" ]; then
        _install_compat_libs_tgz
    fi

    if [ "${ARCH}" = "arm64" ]; then
        if ! dpkg -i aerospike/aerospike-server-*.deb; then
            if ! dpkg --configure -a; then true; fi
            sleep 2
        fi
        if ! dpkg --configure -a; then true; fi
    else
        dpkg -i aerospike/aerospike-server-*.deb
    fi
    command -v asd >/dev/null 2>&1 || {
        echo "ERROR: asd not installed" >&2
        exit 1
    }
    rm -rf /opt/aerospike/bin

    _install_tools_from_tgz

    rm -rf aerospike
    for pkg in binutils xz-utils curl procps; do
        if ! dpkg --purge "${pkg}"; then
            echo "Note: keeping ${pkg} (has reverse dependencies)"
        fi
    done
    if ! apt-get autoremove -y; then true; fi
    rm -rf /var/lib/apt/lists/*
fi

unset DEBIAN_FRONTEND
echo "done"
AEROSPIKE_INSTALL

# Add the Aerospike configuration specific to this dockerfile
COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf

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
