#!/usr/bin/env bash
# Ubuntu/Debian: install via deb (tgz bundle or native .deb). Do not use on UBI/RHEL.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Install dependencies
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
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

# Detect Ubuntu version for compat-libs logic: 22.04 (Jammy) needs Focal-only; 24.04 (Noble) keeps Focal+Jammy for 8.1.
ubuntu_version=""
if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    ubuntu_version="${VERSION_ID:-}"
fi

# OpenSSL 1.1 and OpenLDAP 2.4/2.5 compatibility (required by some Aerospike server builds; Ubuntu 24.04+ has newer only)
# Direct .deb download when apt cannot reach extra repos (e.g. CI)
# On arm64: install full heimdal stack via dpkg (Focal .debs) so we never use apt-get install -f for heimdal (apt resolver fails with "not installable" on Jammy).
install_compat_libs() {
    local arch="${1:-$(dpkg --print-architecture)}"
    local base="https://archive.ubuntu.com/ubuntu/pool/main"
    local base_ports="https://ports.ubuntu.com/ubuntu-ports/pool/main"
    local tmpdir="/tmp/compat-debs"
    mkdir -p "${tmpdir}"
    local h_base="${base}/h/heimdal"
    [ "${arch}" = "arm64" ] && h_base="${base_ports}/h/heimdal"
    local h_ver="7.7.0+dfsg-1ubuntu1"
    # Focal heimdal stack (dependency order); libldap-2.4-2 Depends: libgssapi3-heimdal and its deps
    local heimdal_debs="libroken18-heimdal libheimbase1-heimdal libasn1-8-heimdal libhcrypto4-heimdal libheimntlm0-heimdal libkrb5-26-heimdal libgssapi3-heimdal"
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
        # arm64: install Focal heimdal stack via dpkg so apt-get install -f never touches heimdal (avoids "not installable" on Jammy)
        if [ "${arch}" = "arm64" ]; then
            for pkg in ${heimdal_debs}; do
                if curl -fsSL "${h_base}/${pkg}_${h_ver}_${arch}.deb" -o "${tmpdir}/${pkg}.deb" 2>/dev/null; then
                    dpkg -i "${tmpdir}/${pkg}.deb" || true
                fi
            done
            dpkg --configure -a || true
            sleep 2
            dpkg --configure -a || true
        fi
        # Allow install -f to fail on arm64 (libc-bin/postinst can segfault under QEMU, leaving packages unconfigured)
        dpkg -i "${tmpdir}/libldap-common.deb" "${tmpdir}/libldap-2.4-2.deb" "${tmpdir}/libldap-2.5-0.deb" "${tmpdir}/libssl1.1.deb" || apt-get install -f -y || true
        if [ "${arch}" = "arm64" ]; then
            dpkg --configure -a || true
            sleep 2
            dpkg --configure -a || true
        fi
        rm -rf "${tmpdir}"
        return 0
    fi
    rm -rf "${tmpdir}"
    return 1
}

compat_arch="$(dpkg --print-architecture)"

# Try apt-get first; add focal/jammy compat repos if needed; fall back to direct .deb download.
# On 22.04 arm64 do not install libgssapi3-heimdal via apt (Focal heimdal deps can be "not installable" on Jammy). Use install_compat_libs with Focal kept in sources so install -f can pull heimdal.
COMPAT_PKGS=(libssl1.1 libldap-2.4-2 libldap-2.5-0)

if ! apt-get install -y --no-install-recommends "${COMPAT_PKGS[@]}" 2>/dev/null; then
    repo_base="https://archive.ubuntu.com/ubuntu"
    [ "${compat_arch}" = "arm64" ] && repo_base="https://ports.ubuntu.com/ubuntu-ports"
    echo "deb [trusted=yes] ${repo_base} focal main" >/etc/apt/sources.list.d/focal-compat.list
    # On 22.04 (Jammy) do not add Jammy compat: apt then treats libldap-2.4-2 as obsolete and install fails.
    # On 24.04 (Noble, 8.1) add Jammy so we can get all three packages; Noble default + Focal + Jammy works.
    if [ "${ubuntu_version}" != "22.04" ]; then
        echo "deb [trusted=yes] ${repo_base} jammy main" >/etc/apt/sources.list.d/jammy-compat.list
    fi
    apt-get update -y 2>/dev/null
    if ! apt-get install -y --no-install-recommends "${COMPAT_PKGS[@]}" 2>/dev/null; then
        rm -f /etc/apt/sources.list.d/focal-compat.list /etc/apt/sources.list.d/jammy-compat.list
        apt-get update -y 2>/dev/null
        if ! install_compat_libs; then
            echo "ERROR: failed to install libssl1.1 / libldap-2.4-2 / libldap-2.5-0 (required for Aerospike server on this base image)"
            exit 1
        fi
        rm -f /etc/apt/sources.list.d/focal-compat.list /etc/apt/sources.list.d/jammy-compat.list
        apt-get update -y 2>/dev/null
    else
        rm -f /etc/apt/sources.list.d/focal-compat.list /etc/apt/sources.list.d/jammy-compat.list
        apt-get update -y 2>/dev/null
    fi
fi
apt-mark manual libssl1.1 libldap-2.4-2 libldap-2.5-0 2>/dev/null || true

# Verify compatibility libs are present (fail build if missing so we don't ship broken images)
# ldconfig can segfault under QEMU arm64; ignore so we can still check by path
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
# Fix any remaining broken/unmet dependencies so purge/autoremove can run (22.04 arm64: already fixed in install_compat_libs with Focal).
apt-get install -f -y || true
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
