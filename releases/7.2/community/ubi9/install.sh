#!/usr/bin/env bash
# UBI/RHEL: install Aerospike server + tools.
# Single source of truth for all RPM-based Docker images.
# Executed from the Dockerfile RUN heredoc (BuildKit); not copied as a separate layer file.
#
# Expected ARG/ENV from Dockerfile:
#   AEROSPIKE_EDITION        community|enterprise|federal
#   AEROSPIKE_X86_64_LINK    download URL (x86_64, tgz or native rpm)
#   AEROSPIKE_SHA_X86_64     SHA256
#   AEROSPIKE_AARCH64_LINK   download URL (aarch64, tgz or native rpm)
#   AEROSPIKE_SHA_AARCH64    SHA256
#   AEROSPIKE_LOCAL_PKG      0|1 (when using -u local dir, packages pre-copied to /tmp)
#
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
set -Eeuo pipefail

# Retry helper for arm64 QEMU emulation flakiness
function _retry() {
    local _i
    for _i in 1 2 3 4 5; do
        if "$@"; then return 0; fi
        sleep $((_i * 5))
    done
    "$@"
}

# Install tools from tgz (rpm2cpio extract)
function _install_tools_from_tgz() {
    shopt -s nullglob
    _tool_rpms=(aerospike/aerospike-tools*.rpm)
    if [ "${#_tool_rpms[@]}" -eq 0 ]; then
        echo "ERROR: no aerospike-tools*.rpm under aerospike/ after tar extract (cwd=$(pwd))" >&2
        ls -la aerospike >&2 || true
        exit 1
    fi
    _tool_rpm_base="${_tool_rpms[0]##*/}"
    if ! rpm2cpio "aerospike/${_tool_rpm_base}" | cpio -idm -D aerospike/pkg; then
        sleep 3
        rpm2cpio "aerospike/${_tool_rpm_base}" | cpio -idm -D aerospike/pkg
    fi

    if [ -d aerospike/pkg/opt/aerospike/bin/ ]; then
        find aerospike/pkg/opt/aerospike/bin/ -exec chown root:root {} +
    fi
    mkdir -p /etc/aerospike
    if [ -f aerospike/pkg/etc/aerospike/astools.conf ]; then
        mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike/
    fi
    if [ ! -e aerospike/pkg/opt/aerospike/bin/asadm ]; then
        echo "ERROR: asadm missing under aerospike/pkg/opt/aerospike/bin after tools extract" >&2
        find aerospike/pkg -maxdepth 6 \( -name asadm -o -name asinfo \) -print >&2
        exit 1
    fi
    if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then
        mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/
    else
        mkdir -p /usr/lib/asadm
        mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/
    fi
    if [ -e /usr/lib/asadm/asadm ]; then
        ln -snf /usr/lib/asadm/asadm /usr/bin/asadm
    fi
    if [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ]; then
        mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/
    fi
    if [ -e /usr/lib/asadm/asinfo ]; then
        ln -snf /usr/lib/asadm/asinfo /usr/bin/asinfo
    fi
}

# ---------------------------------------------------------------------------
# Main install logic
# ---------------------------------------------------------------------------

ARCH="$(uname -m)"

# Install build dependencies (with retry for arm64 QEMU). procps-ng provides ps(1); kept at runtime.
_retry microdnf install -y --setopt=install_weak_deps=0 \
    findutils tar gzip xz ca-certificates cpio shadow-utils procps-ng

# Install curl (curl-minimal preferred on ubi-minimal; fallback to full curl)
if ! command -v curl >/dev/null 2>&1; then
    if ! _retry microdnf install -y curl-minimal; then
        _retry microdnf install -y curl
    fi
fi
command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl not found" >&2
    exit 1
}

# as-tini-static is COPY'd in the Dockerfile from static/tini/ (no RUN-time GitHub fetch).
test -x /usr/bin/as-tini-static || {
    echo "ERROR: /usr/bin/as-tini-static missing (Dockerfile vendored tini step)" >&2
    exit 1
}

# Select arch-specific package link and SHA
if [ "${ARCH}" = "x86_64" ]; then
    pkg_link="${AEROSPIKE_X86_64_LINK:-}"
    sha256="${AEROSPIKE_SHA_X86_64:-}"
else
    pkg_link="${AEROSPIKE_AARCH64_LINK:-}"
    sha256="${AEROSPIKE_SHA_AARCH64:-}"
fi

# --- Install: local native .rpm (AEROSPIKE_LOCAL_PKG=1) ---
if [ "${AEROSPIKE_LOCAL_PKG:-0}" = "1" ]; then
    if [ "${ARCH}" = "x86_64" ]; then
        cp /tmp/server_x86_64.rpm server.rpm
        [ -f /tmp/server_x86_64.rpm.sha256 ] && {
            pkg_hash=$(awk '{print $1}' /tmp/server_x86_64.rpm.sha256)
            echo "${pkg_hash}  server.rpm" | sha256sum -c -
        }
    else
        cp /tmp/server_aarch64.rpm server.rpm
        [ -f /tmp/server_aarch64.rpm.sha256 ] && {
            pkg_hash=$(awk '{print $1}' /tmp/server_aarch64.rpm.sha256)
            echo "${pkg_hash}  server.rpm" | sha256sum -c -
        }
    fi

    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
        _retry microdnf install -y --setopt=install_weak_deps=0 openldap
    fi

    if [ "${ARCH}" = "aarch64" ]; then
        if ! rpm -i --excludedocs server.rpm; then
            sleep 3
            rpm -i --excludedocs server.rpm || {
                echo "ERROR: rpm -i server.rpm failed" >&2
                exit 1
            }
        fi
    else
        rpm -i --excludedocs server.rpm
    fi
    command -v asd >/dev/null 2>&1 || {
        echo "ERROR: asd not installed" >&2
        exit 1
    }
    mkdir -p /var/{log,run}/aerospike

    rm -f server.rpm
    microdnf clean all || echo "WARNING: microdnf clean failed" >&2
    rm -rf /var/cache/yum /var/cache/dnf

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
    mkdir -p /var/{log,run}/aerospike /licenses
    cp aerospike/LICENSE /licenses

    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
        _retry microdnf install -y --setopt=install_weak_deps=0 openldap
    fi

    if ! rpm -i --excludedocs aerospike/aerospike-server-*.rpm; then
        sleep 3
        rpm -i --excludedocs aerospike/aerospike-server-*.rpm || {
            echo "ERROR: rpm -i aerospike-server failed (install missing deps instead of --nodeps)" >&2
            exit 1
        }
    fi
    command -v asd >/dev/null 2>&1 || {
        echo "ERROR: asd not installed" >&2
        exit 1
    }
    rm -rf /opt/aerospike/bin

    _install_tools_from_tgz

    rm -rf aerospike
    microdnf remove -y findutils tar gzip xz cpio || echo "WARNING: microdnf remove build deps failed" >&2
    microdnf clean all || echo "WARNING: microdnf clean failed" >&2
    rm -rf /var/cache/yum /var/cache/dnf
fi

echo "done"
