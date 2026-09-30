#!/usr/bin/env bash
# Ubuntu/Debian: install Aerospike server from a native .deb (no tools bundle).
# The only install path: images are built from native packages, by default from
# the JFrog database-deb-prod-public-local repo.
#
# Two modes, selected at generation time by substituting the placeholders:
#   Remote: __SERVER_URL_AMD64__ / __SERVER_SHA_AMD64__ are HTTP URLs+SHAs; the
#           .deb is downloaded via curl at build time.
#   Local:  placeholders are substituted to empty strings; the .deb is pre-staged
#           in /tmp/aerospike/ via a Dockerfile COPY instruction before this block.
#
# __ASADM_URL_AMD64__ / __ASADM_SHA_AMD64__ follow the same two modes for the
# standalone aerospike-asadm package. asadm is required in every image, so they
# are substituted to empty strings only under --no-asadm: a target with no asadm
# for an arch it builds is refused by the generator rather than emitted.
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
# Downloads are named to match the arch-qualified glob used by the install step
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
# Arch-qualified because a local build stages both arches through one COPY.
# Installing server, tools and asadm together lets apt resolve their
# dependencies inline. (aerospike-tools may declare a hard Depends on curl; in
# that case curl stays installed after the autoremove at the end.)
apt-get install -y --no-install-recommends /tmp/aerospike/aerospike-*_"${ARCH}".deb

# ---------------------------------------------------------------------------
# Post-install housekeeping
# ---------------------------------------------------------------------------
mkdir -p /etc/aerospike /licenses /var/log/aerospike /var/run/aerospike
# /licenses/ is where Red Hat certification expects the license to be.
cp /opt/aerospike/doc/LICENSE /licenses/
if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
    if [ -f /tmp/aerospike/features.conf ]; then
        cp /tmp/aerospike/features.conf /etc/aerospike/features.conf
    fi
fi
rm -rf /tmp/aerospike
apt-mark auto curl
apt-get autoremove -y --purge
rm -rf /var/lib/apt/lists/*
