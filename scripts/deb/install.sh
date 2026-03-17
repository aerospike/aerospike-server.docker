#!/usr/bin/env bash
# Ubuntu/Debian: install via deb (tgz bundle or native .deb). Do not use on UBI/RHEL.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Install dependencies
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y || true
# On arm64 cross-build (QEMU), libc-bin postinst can segfault (exit 139). Allow install to complete and finish configure after.
if [ "$(dpkg --print-architecture)" = "arm64" ]; then
    apt-get install -y --no-install-recommends ca-certificates curl binutils xz-utils || true
    dpkg --configure -a || true
    sleep 2
    dpkg --configure -a || true
else
    apt-get install -y --no-install-recommends ca-certificates curl binutils xz-utils
fi
# Ensure required tools are present (arm64 may have had transient libc-bin failure)
command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl not found after apt-get install"
    exit 1
}

# Download tini
ARCH="$(dpkg --print-architecture)"
if [ "${ARCH}" = "amd64" ]; then
    sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940
    suffix=""
else
    sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b
    suffix="-arm64"
fi
curl -fsSL "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" -o /usr/bin/as-tini-static
echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -
chmod +x /usr/bin/as-tini-static

# Download and install server (tgz bundle or native deb)
if [ "${ARCH}" = "amd64" ]; then
    pkg_link="${AEROSPIKE_X86_64_LINK}"
    sha256="${AEROSPIKE_SHA_X86_64}"
    tools_link="${AEROSPIKE_TOOLS_X86_64_LINK:-}"
    tools_sha="${AEROSPIKE_TOOLS_SHA_X86_64:-}"
else
    pkg_link="${AEROSPIKE_AARCH64_LINK}"
    sha256="${AEROSPIKE_SHA_AARCH64}"
    tools_link="${AEROSPIKE_TOOLS_AARCH64_LINK:-}"
    tools_sha="${AEROSPIKE_TOOLS_SHA_AARCH64:-}"
fi

if [ "${AEROSPIKE_PKG_FORMAT:-tgz}" = "tgz" ]; then
    curl -fsSL "${pkg_link}" -o aerospike.tgz
    [ -n "${sha256}" ] && echo "${sha256} aerospike.tgz" | sha256sum -c -
    mkdir aerospike && tar xzf aerospike.tgz --strip-components=1 -C aerospike
    dpkg -i aerospike/aerospike-server-*.deb
    mkdir -p /var/{log,run}/aerospike /licenses
    cp aerospike/LICENSE /licenses
    # Install tools from tgz
    mkdir -p aerospike/pkg
    ar -x aerospike/aerospike-tools*.deb --output aerospike/pkg
    tar xf aerospike/pkg/data.tar.xz -C aerospike/pkg/
else
    # Native deb: from local /tmp (when -u local dir) or download (SHA optional, e.g. JFrog)
    # If .sha256 is present we verify; if not we skip verification and do not exit.
    if [ "${AEROSPIKE_LOCAL_PKG:-0}" = "1" ]; then
        if [ "${ARCH}" = "amd64" ]; then
            cp /tmp/server_amd64.deb server.deb
            [ -f /tmp/server_amd64.deb.sha256 ] && {
                hash=$(awk '{print $1}' /tmp/server_amd64.deb.sha256)
                echo "${hash}  server.deb" | sha256sum -c -
            }
        else
            cp /tmp/server_arm64.deb server.deb
            [ -f /tmp/server_arm64.deb.sha256 ] && {
                hash=$(awk '{print $1}' /tmp/server_arm64.deb.sha256)
                echo "${hash}  server.deb" | sha256sum -c -
            }
        fi
    else
        curl -fsSL "${pkg_link}" -o server.deb
        [ -n "${sha256}" ] && echo "${sha256} server.deb" | sha256sum -c -
    fi
    dpkg -i server.deb
    mkdir -p /var/{log,run}/aerospike /licenses
    [ -n "${tools_link}" ] && {
        curl -fsSL "${tools_link}" -o tools.deb
        [ -n "${tools_sha}" ] && echo "${tools_sha} tools.deb" | sha256sum -c -
        mkdir -p aerospike/pkg
        ar -x tools.deb --output aerospike/pkg
        tar xf aerospike/pkg/data.tar.xz -C aerospike/pkg/
    }
fi

# Install tools (paths from tgz or from native tools.deb extract)
if [ -d aerospike/pkg/opt/aerospike/bin ]; then
    find aerospike/pkg/opt/aerospike/bin/ -user aerospike -group aerospike -exec chown root:root {} + 2>/dev/null || true
    mkdir -p /etc/aerospike
    mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike
    if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then
        mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/
    else
        mkdir -p /usr/lib/asadm && mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/
    fi
    ln -sf /usr/lib/asadm/asadm /usr/bin/asadm
    [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ] && mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/
    ln -sf /usr/lib/asadm/asinfo /usr/bin/asinfo
fi

# Cleanup
dpkg --configure -a || true
if [ "${AEROSPIKE_PKG_FORMAT:-tgz}" = "tgz" ]; then
    rm -rf aerospike aerospike.tgz /var/lib/apt/lists/*
else
    rm -rf aerospike server.deb tools.deb /var/lib/apt/lists/*
fi
# On arm64/QEMU, dpkg config can leave "Unmet dependencies"; allow purge/autoremove to fail so build still completes
apt-get purge -y curl binutils xz-utils || true
apt-get autoremove -y || true
apt-get clean -y
echo "done"
