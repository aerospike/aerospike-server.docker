#!/usr/bin/env bash
# UBI/RHEL: install Aerospike server + tools.
# Single source of truth for all RPM-based Docker images.
# Inlined into the Dockerfile as a `RUN \` block by lib/sh_to_dockerfile_run.sh
# (Docker Official Images rejects both BuildKit heredocs and COPY of build-time
# scripts; the accepted pattern is all logic inline in the Dockerfile).
#
# Package URL/SHA placeholders (__PKG_URL_X86_64__, __PKG_SHA_X86_64__,
# __PKG_URL_AARCH64__, __PKG_SHA_AARCH64__) are substituted by lib/emit.sh at
# generation time.  Tini 1.0.1 URLs and SHAs are hardcoded (fixed release).
#
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Install curl and resolve arch-specific links
# ---------------------------------------------------------------------------
ARCH="$(rpm --eval '%{_arch}')"
# curl-minimal is preferred on ubi-minimal; fall back to full curl if absent.
if ! command -v curl >/dev/null 2>&1; then
    if ! microdnf install -y curl-minimal; then
        microdnf install -y curl
    fi
fi
if [ "${ARCH}" = "x86_64" ]; then
    tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static'
    tiniSha='d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940'
    pkgLink='__PKG_URL_X86_64__'
    pkgSha='__PKG_SHA_X86_64__'
elif [ "${ARCH}" = "aarch64" ]; then
    tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'
    tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'
    pkgLink='__PKG_URL_AARCH64__'
    pkgSha='__PKG_SHA_AARCH64__'
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
# findutils: provides find(1) invoked by aerospike-server %post scriptlets.
# shadow-utils: provides groupadd/useradd invoked by %pre/%post scriptlets;
#               retained in the image (needed by many runtime exec workflows).
# tar/gzip: extract the TGZ bundle; removed in cleanup.
microdnf install -y --setopt=install_weak_deps=0 findutils shadow-utils tar gzip
mkdir -p /tmp/aerospike
curl -fL -o /tmp/aerospike/pkg.tgz "${pkgLink}"
echo "${pkgSha} */tmp/aerospike/pkg.tgz" | sha256sum --strict --check -
tar -xzf /tmp/aerospike/pkg.tgz --strip-components=1 -C /tmp/aerospike
rm /tmp/aerospike/pkg.tgz

# ---------------------------------------------------------------------------
# Install Aerospike server and tools
# ---------------------------------------------------------------------------
# Install both packages together with rpm -i so the package manager resolves
# dependency ordering and %post scriptlets run in the correct sequence.
# openldap: required by enterprise/federal server at runtime for LDAP auth.
if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
    microdnf install -y --setopt=install_weak_deps=0 openldap
fi
rpm -i --excludedocs \
    /tmp/aerospike/aerospike-server-*.rpm \
    /tmp/aerospike/aerospike-tools*.rpm

# ---------------------------------------------------------------------------
# Post-install housekeeping
# ---------------------------------------------------------------------------
mkdir -p /licenses /var/log/aerospike /var/run/aerospike
cp /tmp/aerospike/LICENSE /licenses/
if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
    if [ -f /tmp/aerospike/features.conf ]; then
        mkdir -p /etc/aerospike
        cp /tmp/aerospike/features.conf /etc/aerospike/features.conf
    fi
fi
rm -rf /tmp/aerospike
microdnf remove -y tar gzip
microdnf clean all
rm -rf /var/cache/yum /var/cache/dnf
