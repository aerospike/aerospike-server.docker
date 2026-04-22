# syntax=docker/dockerfile:1
#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi9/ubi-minimal:9.7" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.0.0.15" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="community"

ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/8.0.0.15/aerospike-server-community_8.0.0.15_tools-13.0.0_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="fb253e6051b62ed4ff51a089d8d28c20913c58cc68e9d8705aa61ba110a33b30"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/8.0.0.15/aerospike-server-community_8.0.0.15_tools-13.0.0_el9_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="8e228843d04f072f356885f49699b14dfd2bb7933105d9cf643293483687be2c"
ARG AEROSPIKE_COMPAT_LIBS="0"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Aerospike tini fork (vendored under static/tini/); see static/tini/SOURCES.txt.
# COPY avoids RUN-time fetch from GitHub (Docker Official / air-gapped / reproducible builds).
# hadolint ignore=DL3042
COPY static/tini/as-tini-static-amd64 static/tini/as-tini-static-arm64 /opt/aerospike-tini/
# TARGETARCH is auto-populated by BuildKit. The empty default keeps the
# legacy builder used by Docker Official Images (DOI) from tripping `set -u`,
# and the RUN below falls back to `uname -m`, so the same Dockerfile works on
# both BuildKit and the legacy builder, on Debian/Ubuntu and UBI/RHEL alike.
ARG TARGETARCH=
RUN case "${TARGETARCH:-$(uname -m)}" in \
        amd64 | x86_64) arch=amd64 ;; \
        arm64 | aarch64) arch=arm64 ;; \
        *) echo "ERROR: unsupported arch ${TARGETARCH:-$(uname -m)} for as-tini-static" >&2; exit 1 ;; \
    esac \
    && cp "/opt/aerospike-tini/as-tini-static-${arch}" /usr/bin/as-tini-static \
    && chmod +x /usr/bin/as-tini-static \
    && rm -rf /opt/aerospike-tini

# Install Aerospike Server and Tools
# hadolint ignore=DL3003,DL3008,DL3041,SC2015
RUN bash <<'AEROSPIKE_INSTALL'
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

STOPSIGNAL SIGTERM

# Tini init set to restart ASD on SIGUSR1 and terminate ASD on SIGTERM
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Execute the run script in foreground mode
CMD ["asd"]
