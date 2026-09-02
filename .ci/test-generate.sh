#!/usr/bin/env bash
# Offline generation tests for the native .deb/.rpm package path.
#
# CI's build.yml only ever runs docker-build.sh against the default
# download.aerospike.com URL, which resolves *.tgz bundles. Nothing there
# reaches the native path -- no committed Dockerfile takes it -- so every
# native-path behaviour would otherwise ship unexercised.
#
# No network, no docker, no published aerospike-asadm needed: package contents
# are never read during generation (fetch_sha_for_link hashes a local file and
# emit.sh only copies it), so zero-byte fixtures drive the whole path. Remote
# resolution is covered by a throwaway python http.server.
#
# Copyright 2014-2026 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)
cd "${SCRIPT_DIR}"

VERSION="8.1.3.0"
LINEAGE="8.1"
WORK=$(mktemp -d)
SRV_PID=""
FAILED=0

cleanup() {
    [ -n "${SRV_PID}" ] && kill "${SRV_PID}" 2>/dev/null
    rm -rf "${WORK}"
    git checkout -- releases/ 2>/dev/null || true
    # -x matters: releases/**/*.deb is gitignored, so a plain clean would leave
    # staged packages behind for the next case to trip over.
    git clean -fdxq releases/ 2>/dev/null || true
}
trap cleanup EXIT

pass() { printf '  ok   %s\n' "$1"; }
fail() {
    printf '  FAIL %s\n     %s\n' "$1" "$2"
    FAILED=$((FAILED + 1))
}
check() { # check <name> <condition-description> <actual> <expected>
    if [ "$3" = "$4" ]; then pass "$1"; else fail "$1" "$2: got [$3] want [$4]"; fi
}

reset() {
    git checkout -- releases/ 2>/dev/null || true
    git clean -fdxq releases/ 2>/dev/null || true
}

# Zero-byte fixtures: generation never reads package contents.
mk_pkgs() { # mk_pkgs <dir> <editions...>
    local dir=$1 ed
    shift
    mkdir -p "${dir}"
    for ed in "$@"; do
        : >"${dir}/aerospike-server-${ed}_${VERSION}-1ubuntu24.04_amd64.deb"
        : >"${dir}/aerospike-server-${ed}_${VERSION}-1ubuntu24.04_arm64.deb"
    done
}
mk_asadm() { # mk_asadm <dir> [version]
    local dir=$1 v=${2:-5.0.3}
    mkdir -p "${dir}"
    : >"${dir}/aerospike-asadm_${v}-1ubuntu24.04_x86_64.deb"
    : >"${dir}/aerospike-asadm_${v}-1ubuntu24.04_aarch64.deb"
}

gen() { ./docker-build.sh -g "$@" >"${WORK}/out.log" 2>&1; }
CTX="releases/${LINEAGE}/enterprise/ubuntu24.04"
staged() { find "${CTX}" -maxdepth 1 -name '*.deb' -exec basename {} \; 2>/dev/null; }
staged_count() { staged | grep -c "$1" || true; }

echo "== promise 1/2: asadm staged from a local -u directory =="
reset
mk_pkgs "${WORK}/a" enterprise
mk_asadm "${WORK}/a"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" || true
check "both asadm arches staged" "asadm files" "$(staged_count asadm)" "2"
check "COPY emitted" "COPY *.deb present" \
    "$(grep -c '^COPY \*\.deb' "${CTX}/Dockerfile" || true)" "1"

echo "== promise 2 negative: --no-asadm stages none =="
reset
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" --no-asadm || true
check "no asadm staged" "asadm files" "$(staged_count asadm)" "0"

echo "== promise 2 precedence: -A wins over an asadm in the -u dir =="
reset
mk_asadm "${WORK}/b" 9.9.9
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" -A "${WORK}/b" || true
check "-A beats -u" "staged asadm version" \
    "$(staged | grep -o '9\.9\.9' | head -1)" "9.9.9"
check "-u asadm not also staged" "5.0.3 files" "$(staged_count '5\.0\.3')" "0"

echo "== local -u makes no outbound request =="
reset
mkdir -p "${WORK}/stub"
cat >"${WORK}/stub/curl" <<'STUB'
#!/bin/bash
for a in "$@"; do case "$a" in http*) echo "$a" >>"${CURL_LOG}" ;; esac; done
exec /usr/bin/curl "$@"
STUB
chmod +x "${WORK}/stub/curl"
CURL_LOG="${WORK}/curl.log"
export CURL_LOG
: >"${CURL_LOG}"
PATH="${WORK}/stub:${PATH}" gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" || true
check "zero http requests" "urls fetched" "$(wc -l <"${CURL_LOG}" | tr -d ' ')" "0"

echo "== promise 5: a run that resolves nothing exits 1 and keeps releases/ =="
reset
before=$(find "releases/${LINEAGE}" -name Dockerfile | wc -l | tr -d ' ')
mkdir -p "${WORK}/none/${VERSION}"
gen "${LINEAGE}" -u "${WORK}/none" && rc=0 || rc=$?
after=$(find "releases/${LINEAGE}" -name Dockerfile 2>/dev/null | wc -l | tr -d ' ')
check "exits 1" "exit code" "${rc}" "1"
check "releases/ intact" "Dockerfile count" "${after}" "${before}"

echo "== promise 6: a single -u file is not handed to the wrong target =="
reset
F="${WORK}/one/aerospike-server-enterprise_${VERSION}-1ubuntu24.04_amd64.deb"
mkdir -p "${WORK}/one"
: >"${F}"
gen "${VERSION}" -e enterprise -d ubuntu24.04 ubi10 -a amd64 -u "${F}" || true
check "deb target generated" "ubuntu24.04 staged deb" \
    "$(staged_count 'aerospike-server')" "1"
check "rpm target skipped" "ubi10 unchanged vs committed" \
    "$(git diff --quiet "releases/${LINEAGE}/enterprise/ubi10/" && echo untouched || echo regenerated)" "untouched"
check "no deb leaked into rpm target" "ubi10 staged packages" \
    "$(find "releases/${LINEAGE}/enterprise/ubi10" -maxdepth 1 \( -name '*.deb' -o -name '*.rpm' \) | wc -l | tr -d ' ')" "0"

echo "== remote resolution + injection rejection (local http server) =="
reset
POOL="${WORK}/repo/pool/noble/aerospike-asadm"
mkdir -p "${POOL}"
: >"${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb"
: >"${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb"
# An index entry that would break out of the single-quoted Dockerfile assignment.
cat >"${POOL}/index.html" <<'IDX'
<html><body>
<a href="aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb">a</a>
<a href="aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb">b</a>
<a href="aerospike-asadm_9.9.9-1ubuntu24.04'$(touch /tmp/as-docker-pwned)'_amd64.deb">c</a>
</body></html>
IDX
# Started without a wrapping subshell so $! is python's own pid -- otherwise
# the trap kills the subshell, python survives, and the next run finds the
# port held by a server rooted at a deleted directory.
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
python3 -m http.server "${PORT}" --bind 127.0.0.1 --directory "${WORK}/repo" >/dev/null 2>&1 &
SRV_PID=$!
for _ in $(seq 1 50); do
    curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null && break
    sleep 0.2
done
curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/" 2>/dev/null ||
    fail "http fixture server" "did not come up on port ${PORT}"
rm -f /tmp/as-docker-pwned
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" \
    -A "http://127.0.0.1:${PORT}/pool/noble/aerospike-asadm" || true
check "remote asadm resolved" "asadmUrl count" \
    "$(grep -c "asadmUrl='http" "${CTX}/Dockerfile" || true)" "2"
check "no quote escaped into Dockerfile" "stray \$( in asadmUrl" \
    "$(grep -c "asadmUrl='[^']*'\\\$(" "${CTX}/Dockerfile" || true)" "0"
check "injected entry not selected" "9.9.9 present" \
    "$(grep -c '9\.9\.9' "${CTX}/Dockerfile" || true)" "0"
check "no command executed" "/tmp/as-docker-pwned" \
    "$(test -e /tmp/as-docker-pwned && echo created || echo absent)" "absent"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "All generation tests passed."
else
    echo "${FAILED} generation test(s) failed."
    exit 1
fi
