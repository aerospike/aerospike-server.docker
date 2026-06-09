#!/usr/bin/env bash
# Ubuntu/Debian: install Aerospike server + tools.
# Single source of truth for all DEB-based Docker images.
# Inlined into the Dockerfile as a `RUN \` block by lib/sh_to_dockerfile_run.sh
# (Docker Official Images rejects both BuildKit heredocs and COPY of build-time
# scripts; the accepted pattern is all logic inline in the Dockerfile).
#
# Package URL/SHA placeholders (__PKG_URL_AMD64__, __PKG_SHA_AMD64__,
# __PKG_URL_ARM64__, __PKG_SHA_ARM64__) are substituted by lib/emit.sh at
# generation time.  Tini 1.0.1 URLs and SHAs are hardcoded (fixed release).
#
# No [trusted=yes] third-party apt suites (DOI / supply-chain policy): only
# packages available from the image's default Ubuntu archives.
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
    pkgLink='__PKG_URL_AMD64__'
    pkgSha='__PKG_SHA_AMD64__'
elif [ "${ARCH}" = "arm64" ]; then
    tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'
    tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'
    pkgLink='__PKG_URL_ARM64__'
    pkgSha='__PKG_SHA_ARM64__'
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
# Fetch and unpack server package
# ---------------------------------------------------------------------------
mkdir -p /tmp/aerospike
curl -fL -o /tmp/aerospike/pkg.tgz "${pkgLink}"
echo "${pkgSha} */tmp/aerospike/pkg.tgz" | sha256sum --strict --check -
tar -xzf /tmp/aerospike/pkg.tgz --strip-components=1 -C /tmp/aerospike

# ---------------------------------------------------------------------------
# Install Aerospike server and tools
# ---------------------------------------------------------------------------
# TGZ contents: newer bundles use underscore server debs; legacy 5.7 uses dotted
# names (e.g. aerospike-server-enterprise-5.7.0.32.ubuntu20.04.x86_64.deb) plus
# bundled aerospike-tools*.deb. The globs below match both layouts.
# apt-get install ./deb pulls many deps; OpenLDAP and libcurl are pinned below because
# some legacy server .debs omit Depends that asd still needs after autoremove.
apt-get install -y --no-install-recommends \
    /tmp/aerospike/aerospike-server-*.deb \
    /tmp/aerospike/aerospike-tools*.deb

# OpenLDAP client libs (liblber, etc.): required at runtime for enterprise/federal asd.
# Some legacy server .debs omit a strict Depends; keep libs after autoremove.
if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
    apt-get install -y --no-install-recommends libldap-2.4-2 \
        || apt-get install -y --no-install-recommends libldap-2.5-0
    apt-mark manual libldap-2.4-2 2>/dev/null || true
    apt-mark manual libldap-2.5-0 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Post-install housekeeping
# ---------------------------------------------------------------------------
mkdir -p /etc/aerospike /licenses /var/log/aerospike /var/run/aerospike
cp /tmp/aerospike/LICENSE /licenses/
if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
    if [ -f /tmp/aerospike/features.conf ]; then
        cp /tmp/aerospike/features.conf /etc/aerospike/features.conf
    fi
fi
rm -rf /tmp/aerospike
# libcurl: asd links libcurl.so.4; marking curl(1) auto + autoremove can remove libcurl
# when server .deb omits Depends (common on legacy packages). Keep the SONAME provider.
apt-get install -y --no-install-recommends libcurl4 \
    || apt-get install -y --no-install-recommends libcurl4t64
apt-mark manual libcurl4 2>/dev/null || true
apt-mark manual libcurl4t64 2>/dev/null || true
# Mark curl as auto-installed so autoremove drops it if nothing else depends on it
# (aerospike-tools may declare a hard Depends on curl; in that case curl stays).
apt-mark auto curl
apt-get autoremove -y --purge
rm -rf /var/lib/apt/lists/*
