#!/usr/bin/env bash
# UBI/RHEL: install Aerospike server from a native .rpm (no tools bundle).
# Used when a TGZ bundle is not available (e.g. local pre-release or staging builds).
#
# Two modes, selected at generation time by substituting the placeholders:
#   Remote: __SERVER_URL_X86_64__ / __SERVER_SHA_X86_64__ are HTTP URLs+SHAs; the
#           .rpm is downloaded via curl at build time.
#   Local:  placeholders are substituted to empty strings; the .rpm is pre-staged
#           in /tmp/aerospike/ via a Dockerfile COPY instruction before this block.
#
# __ASADM_URL_X86_64__ / __ASADM_SHA_X86_64__ follow the same two modes for the
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
ARCH="$(rpm --eval '%{_arch}')"
# Aerospike publishes some packages (notably aerospike-asadm) with the dpkg arch
# spelling rather than the kernel one, so both are matched when collecting.
if [ "${ARCH}" = "x86_64" ]; then
    ALT_ARCH="amd64"
elif [ "${ARCH}" = "aarch64" ]; then
    ALT_ARCH="arm64"
fi
# curl-minimal is preferred on ubi-minimal; fall back to full curl if absent.
if ! command -v curl >/dev/null 2>&1; then
    if ! microdnf install -y curl-minimal; then
        microdnf install -y curl
    fi
fi
if [ "${ARCH}" = "x86_64" ]; then
    tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static'
    tiniSha='d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940'
    serverUrl='__SERVER_URL_X86_64__'
    serverSha='__SERVER_SHA_X86_64__'
    asadmUrl='__ASADM_URL_X86_64__'
    asadmSha='__ASADM_SHA_X86_64__'
elif [ "${ARCH}" = "aarch64" ]; then
    tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'
    tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'
    serverUrl='__SERVER_URL_AARCH64__'
    serverSha='__SERVER_SHA_AARCH64__'
    asadmUrl='__ASADM_URL_AARCH64__'
    asadmSha='__ASADM_SHA_AARCH64__'
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
# shadow-utils: provides groupadd/useradd used by aerospike-server %post scriptlet.
# findutils: provides find(1) used by aerospike-server %post scriptlet.
# Downloads are named to match the arch-qualified globs used by the install step
# below, so remote and pre-staged packages are collected the same way.
microdnf install -y --setopt=install_weak_deps=0 findutils shadow-utils
mkdir -p /tmp/aerospike
if [ -n "${serverUrl}" ]; then
    curl -fL -o "/tmp/aerospike/aerospike-server-dl.${ARCH}.rpm" "${serverUrl}"
    echo "${serverSha} */tmp/aerospike/aerospike-server-dl.${ARCH}.rpm" | sha256sum --strict --check -
fi
if [ -n "${asadmUrl}" ]; then
    curl -fL -o "/tmp/aerospike/aerospike-asadm-dl.${ARCH}.rpm" "${asadmUrl}"
    echo "${asadmSha} */tmp/aerospike/aerospike-asadm-dl.${ARCH}.rpm" | sha256sum --strict --check -
fi

# ---------------------------------------------------------------------------
# Install Aerospike server
# ---------------------------------------------------------------------------
if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
    microdnf install -y --setopt=install_weak_deps=0 openldap
fi
# Collect all arch-matching packages in /tmp/aerospike/:
#   - aerospike-server-*.${ARCH}.rpm  (required)
#   - aerospike-tools-*.${ARCH}.rpm   (optional; staged when server declares a
#                                      hard Requires on aerospike-tools)
#   - aerospike-asadm-*.${ARCH}.rpm   (optional; downloaded or staged above,
#                                      including arch-independent .noarch.rpm)
pkgs=()
serverFound=false
for f in /tmp/aerospike/aerospike-server-*."${ARCH}".rpm; do
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
# aerospike-asadm* rather than aerospike-asadm-*: the resolver accepts both
# separators (aerospike-asadm[-_]), so requiring the hyphen here would let a
# locally staged aerospike-asadm_5.0.3-....rpm be resolved, logged as included
# and copied in, then matched by none of these globs -- an image that ships
# without asadm while the generation log says it has it. The server and tools
# packages still cannot match: their names begin aerospike-server- /
# aerospike-tools-.
for f in /tmp/aerospike/aerospike-tools-*."${ARCH}".rpm \
    /tmp/aerospike/aerospike-asadm*."${ARCH}".rpm \
    /tmp/aerospike/aerospike-asadm*."${ALT_ARCH}".rpm \
    /tmp/aerospike/aerospike-asadm*.noarch.rpm; do
    if [ -f "${f}" ]; then pkgs+=("${f}"); fi
done
rpm -i --excludedocs "${pkgs[@]}"

# ---------------------------------------------------------------------------
# Post-install housekeeping
# ---------------------------------------------------------------------------
mkdir -p /licenses /var/log/aerospike /var/run/aerospike
if [ -f /tmp/aerospike/LICENSE ]; then
    cp /tmp/aerospike/LICENSE /licenses/
fi
if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then
    if [ -f /tmp/aerospike/features.conf ]; then
        mkdir -p /etc/aerospike
        cp /tmp/aerospike/features.conf /etc/aerospike/features.conf
    fi
fi
rm -rf /tmp/aerospike
microdnf clean all
rm -rf /var/cache/yum /var/cache/dnf
