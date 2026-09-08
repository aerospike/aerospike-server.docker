#!/usr/bin/env bash
# Ubuntu/Debian: install Aerospike server from a native .deb (no tools bundle).
# Used when a TGZ bundle is not available (e.g. local pre-release or staging builds).
#
# Two modes, selected at generation time by substituting the placeholders:
#   Remote: __SERVER_URL_AMD64__ / __SERVER_SHA_AMD64__ are HTTP URLs+SHAs; the
#           .deb is downloaded via curl at build time.
#   Local:  placeholders are substituted to empty strings; the .deb is pre-staged
#           in /tmp/aerospike/ via a Dockerfile COPY instruction before this block.
#
# __ASADM_URL_AMD64__ / __ASADM_SHA_AMD64__ follow the same two modes for the
# standalone aerospike-asadm package. They are substituted to empty strings when
# asadm is not published for this distro/arch, which skips it entirely; the TGZ
# install path never uses this script because aerospike-tools already ships asadm.
#
# Tini 1.0.1 URLs and SHAs are hardcoded (fixed release).
#
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Install curl and resolve arch-specific links
# ---------------------------------------------------------------------------
apt-get update
apt-get install -y --no-install-recommends curl
ARCH="$(dpkg --print-architecture)"
# Aerospike publishes some packages (notably aerospike-asadm) with the kernel
# arch spelling rather than the dpkg one, so both are matched when collecting.
if [ "${ARCH}" = "amd64" ]; then
    ALT_ARCH="x86_64"
elif [ "${ARCH}" = "arm64" ]; then
    ALT_ARCH="aarch64"
fi
if [ "${ARCH}" = "amd64" ]; then
    tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static'
    tiniSha='d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940'
    serverUrl='__SERVER_URL_AMD64__'
    serverSha='__SERVER_SHA_AMD64__'
    asadmUrl='__ASADM_URL_AMD64__'
    asadmSha='__ASADM_SHA_AMD64__'
elif [ "${ARCH}" = "arm64" ]; then
    tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'
    tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'
    serverUrl='__SERVER_URL_ARM64__'
    serverSha='__SERVER_SHA_ARM64__'
    asadmUrl='__ASADM_URL_ARM64__'
    asadmSha='__ASADM_SHA_ARM64__'
else
    echo >&2 "error: unsupported architecture '${ARCH}'"
    exit 1
fi

# ---------------------------------------------------------------------------
# Fetch and install tini
# ---------------------------------------------------------------------------
curl -fL -o /usr/bin/as-tini-static "${tiniUrl}"
echo "${tiniSha} */usr/bin/as-tini-static" | sha256sum --strict --check -
chmod +x /usr/bin/as-tini-static

# ---------------------------------------------------------------------------
# Download server and asadm packages (remote builds only; local builds use COPY)
# ---------------------------------------------------------------------------
# Downloads are named to match the arch-qualified globs used by the install step
# below, so remote and pre-staged packages are collected the same way.
mkdir -p /tmp/aerospike
if [ -n "${serverUrl}" ]; then
    curl -fL -o "/tmp/aerospike/aerospike-server-dl_${ARCH}.deb" "${serverUrl}"
    echo "${serverSha} */tmp/aerospike/aerospike-server-dl_${ARCH}.deb" | sha256sum --strict --check -
fi
if [ -n "${asadmUrl}" ]; then
    curl -fL -o "/tmp/aerospike/aerospike-asadm-dl_${ARCH}.deb" "${asadmUrl}"
    echo "${asadmSha} */tmp/aerospike/aerospike-asadm-dl_${ARCH}.deb" | sha256sum --strict --check -
fi

# ---------------------------------------------------------------------------
# Install Aerospike server
# ---------------------------------------------------------------------------
# Collect all arch-matching packages in /tmp/aerospike/:
#   - aerospike-server-*_${ARCH}.deb  (required)
#   - aerospike-tools-*_${ARCH}.deb   (optional; staged when server declares a
#                                      hard Depends on aerospike-tools)
#   - aerospike-asadm*_${ARCH}.deb    (optional; downloaded or staged above,
#                                      including arch-independent _all.deb)
# Installing them together lets apt resolve the dependencies inline.
# (aerospike-tools may also declare a hard Depends on curl; in that case curl
# stays installed after the autoremove at the end.)
pkgs=()
serverFound=false
for f in /tmp/aerospike/aerospike-server-*_"${ARCH}".deb \
    /tmp/aerospike/aerospike-server-*_"${ALT_ARCH}".deb; do
    if [ -f "${f}" ]; then
        pkgs+=("${f}")
        serverFound=true
    fi
done
# The server package is the only required one; asadm/tools alone must never
# produce an image, so the guard tracks the server specifically.
if [ "${serverFound}" = false ]; then
    echo >&2 "error: no server package found in /tmp/aerospike/ for arch '${ARCH}'"
    exit 1
fi
for f in /tmp/aerospike/aerospike-tools-*_"${ARCH}".deb \
    /tmp/aerospike/aerospike-tools-*_"${ALT_ARCH}".deb \
    /tmp/aerospike/aerospike-asadm*_"${ARCH}".deb \
    /tmp/aerospike/aerospike-asadm*_"${ALT_ARCH}".deb \
    /tmp/aerospike/aerospike-asadm*_all.deb; do
    if [ -f "${f}" ]; then pkgs+=("${f}"); fi
done
apt-get install -y --no-install-recommends "${pkgs[@]}"

# ---------------------------------------------------------------------------
# Post-install housekeeping
# ---------------------------------------------------------------------------
mkdir -p /etc/aerospike /licenses /var/log/aerospike /var/run/aerospike
if [ -f /tmp/aerospike/LICENSE ]; then
    cp /tmp/aerospike/LICENSE /licenses/
fi
if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
    if [ -f /tmp/aerospike/features.conf ]; then
        cp /tmp/aerospike/features.conf /etc/aerospike/features.conf
    fi
fi
rm -rf /tmp/aerospike
apt-mark auto curl
apt-get autoremove -y --purge
rm -rf /var/lib/apt/lists/*
