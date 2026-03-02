#!/usr/bin/env bash
# Ubuntu/Debian: install via deb (tgz bundle or native .deb). Do not use on UBI/RHEL.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Install dependencies
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl binutils xz-utils

# OpenSSL 1.1 and OpenLDAP 2.4/2.5 compatibility (required by some Aerospike server builds; Ubuntu 24.04+ has newer only)
# Direct .deb download when apt cannot reach extra repos (e.g. CI)
install_compat_libs() {
    local arch="${1:-$(dpkg --print-architecture)}"
    local base="https://archive.ubuntu.com/ubuntu/pool/main"
    local base_ports="https://ports.ubuntu.com/ubuntu-ports/pool/main"
    local tmpdir="/tmp/compat-debs"
    mkdir -p "${tmpdir}"
    # Focal: libssl1.1, libldap-2.4-2 + libldap-common (2.4). Jammy: libldap-2.5-0 + libldap-common (2.5, satisfies both)
    local ssl_url="${base}/o/openssl/libssl1.1_1.1.1f-1ubuntu2.24_${arch}.deb"
    [ "${arch}" = "arm64" ] && ssl_url="${base_ports}/o/openssl/libssl1.1_1.1.1f-1ubuntu2.24_${arch}.deb"
    local ldap_common_jammy="${base}/o/openldap/libldap-common_2.5.16+dfsg-0ubuntu0.22.04.2_all.deb"
    local ldap24_url="${base}/o/openldap/libldap-2.4-2_2.4.49+dfsg-2ubuntu1.10_${arch}.deb"
    [ "${arch}" = "arm64" ] && ldap24_url="${base_ports}/o/openldap/libldap-2.4-2_2.4.49+dfsg-2ubuntu1.10_${arch}.deb"
    local ldap25_url="${base}/o/openldap/libldap-2.5-0_2.5.16+dfsg-0ubuntu0.22.04.2_${arch}.deb"
    [ "${arch}" = "arm64" ] && ldap25_url="${base_ports}/o/openldap/libldap-2.5-0_2.5.16+dfsg-0ubuntu0.22.04.2_${arch}.deb"
    if curl -fsSL "${ssl_url}" -o "${tmpdir}/libssl1.1.deb" &&
        curl -fsSL "${ldap_common_jammy}" -o "${tmpdir}/libldap-common.deb" &&
        curl -fsSL "${ldap24_url}" -o "${tmpdir}/libldap-2.4-2.deb" &&
        curl -fsSL "${ldap25_url}" -o "${tmpdir}/libldap-2.5-0.deb"; then
        dpkg -i "${tmpdir}/libldap-common.deb" "${tmpdir}/libldap-2.4-2.deb" "${tmpdir}/libldap-2.5-0.deb" "${tmpdir}/libssl1.1.deb" || apt-get install -f -y
        rm -rf "${tmpdir}"
        return 0
    fi
    rm -rf "${tmpdir}"
    return 1
}

if ! apt-get install -y --no-install-recommends libssl1.1 libldap-2.4-2 libldap-2.5-0 2>/dev/null; then
    # Try Focal (20.04) + Jammy (22.04) repos: Focal has libssl1.1 and libldap-2.4-2, Jammy has libldap-2.5-0.
    # arm64 packages are on ports.ubuntu.com; archive.ubuntu.com returns 404 for jammy/focal arm64.
    compat_arch="$(dpkg --print-architecture)"
    repo_base="https://archive.ubuntu.com/ubuntu"
    [ "${compat_arch}" = "arm64" ] && repo_base="https://ports.ubuntu.com/ubuntu-ports"
    echo "deb [trusted=yes] ${repo_base} focal main" >/etc/apt/sources.list.d/focal-compat.list
    echo "deb [trusted=yes] ${repo_base} jammy main" >/etc/apt/sources.list.d/jammy-compat.list
    apt-get update -y 2>/dev/null
    if ! apt-get install -y --no-install-recommends libssl1.1 libldap-2.4-2 libldap-2.5-0 2>/dev/null; then
        rm -f /etc/apt/sources.list.d/focal-compat.list /etc/apt/sources.list.d/jammy-compat.list
        apt-get update -y 2>/dev/null
        if ! install_compat_libs; then
            echo "ERROR: failed to install libssl1.1 / libldap-2.4-2 / libldap-2.5-0 (required for Aerospike server on this base image)"
            exit 1
        fi
    else
        rm -f /etc/apt/sources.list.d/focal-compat.list /etc/apt/sources.list.d/jammy-compat.list
        apt-get update -y 2>/dev/null
    fi
fi
apt-mark manual libssl1.1 libldap-2.4-2 libldap-2.5-0 2>/dev/null || true

# Verify compatibility libs are present (fail build if missing so we don't ship broken images)
ldconfig 2>/dev/null || true
for lib in libcrypto.so.1.1 liblber-2.4.so.2 liblber-2.5.so.0; do
    if ! ldconfig -p 2>/dev/null | grep -q "${lib}" &&
        ! [ -f "/usr/lib/x86_64-linux-gnu/${lib}" ] &&
        ! [ -f "/usr/lib/aarch64-linux-gnu/${lib}" ]; then
        echo "ERROR: ${lib} not found (Aerospike server requires it on this base image)"
        exit 1
    fi
done

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
if [ "${AEROSPIKE_PKG_FORMAT:-tgz}" = "tgz" ]; then
    rm -rf aerospike aerospike.tgz /var/lib/apt/lists/*
else
    rm -rf aerospike server.deb tools.deb /var/lib/apt/lists/*
fi
apt-get purge -y curl binutils xz-utils
apt-get autoremove -y
apt-get clean -y
echo "done"
