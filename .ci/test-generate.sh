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
# resolution is covered by a throwaway python http.server, rooted so that
# is_artifactory_url matches and the real JFrog pool/ mapping is exercised.
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
SCENARIOS=0
EXPECTED_SCENARIOS=24
CURRENT_LOG="${WORK}/out.log"

FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

# reset() and cleanup() run `git checkout`/`git clean -fdx` over releases/, which
# discards uncommitted edits there and -- because releases/**/*.deb is gitignored
# -- deletes packages a developer staged for a -u build, often the only copy.
# Refuse rather than destroy. CI always starts from a fresh checkout.
if [ "${CI:-}" != "true" ] && [ "${FORCE}" = false ]; then
    if [ -n "$(git status --porcelain --ignored -- releases/ 2>/dev/null)" ]; then
        echo "refusing to run: releases/ has uncommitted or ignored files." >&2
        echo "This suite resets releases/ with 'git checkout' and 'git clean -fdx'," >&2
        echo "which would delete them. Commit, stash or remove them first, or" >&2
        echo "re-run with --force if you are certain nothing there matters." >&2
        git status --porcelain --ignored -- releases/ >&2
        exit 2
    fi
fi

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
    if [ -s "${CURRENT_LOG}" ]; then
        printf '     --- last 20 lines of generator output ---\n'
        tail -20 "${CURRENT_LOG}" | sed 's/^/     | /'
    fi
    FAILED=$((FAILED + 1))
}
check() { # check <name> <condition-description> <actual> <expected>
    if [ "$3" = "$4" ]; then pass "$1"; else fail "$1" "$2: got [$3] want [$4]"; fi
}
check_ne() { # check_ne <name> <condition-description> <actual> <not-expected>
    if [ "$3" != "$4" ]; then pass "$1"; else fail "$1" "$2: got [$3], wanted anything else"; fi
}

# Each scenario gets its own log, kept for the whole run so fail() can quote the
# generator output that explains the failure instead of discarding it.
scenario() {
    SCENARIOS=$((SCENARIOS + 1))
    CURRENT_LOG="${WORK}/scenario-${SCENARIOS}.log"
    : >"${CURRENT_LOG}"
    echo "== $1 =="
    git checkout -- releases/ 2>/dev/null || true
    git clean -fdxq releases/ 2>/dev/null || true
}

# Zero-byte fixtures with real sidecars: generation never reads package
# contents, but it does read the .sha256 next to them, and asserting the
# emitted digest per arch is the only thing that can catch an arch mix-up.
sha_of() { sha256sum "$1" | cut -f1 -d' '; }
mk_pkg() { # mk_pkg <path>
    mkdir -p "$(dirname "$1")"
    : >"$1"
    sha_of "$1" >"$1.sha256"
}
mk_pkgs() { # mk_pkgs <dir> <editions...>
    local dir=$1 ed
    shift
    for ed in "$@"; do
        mk_pkg "${dir}/aerospike-server-${ed}_${VERSION}-1ubuntu24.04_amd64.deb"
        mk_pkg "${dir}/aerospike-server-${ed}_${VERSION}-1ubuntu24.04_arm64.deb"
    done
}
mk_asadm() { # mk_asadm <dir> [version] [distro]
    local dir=$1 v=${2:-5.0.3} d=${3:-ubuntu24.04}
    mk_pkg "${dir}/aerospike-asadm_${v}-1${d}_x86_64.deb"
    mk_pkg "${dir}/aerospike-asadm_${v}-1${d}_aarch64.deb"
}

gen() { ./docker-build.sh -g "$@" >"${CURRENT_LOG}" 2>&1; }
CTX="releases/${LINEAGE}/enterprise/ubuntu24.04"
DF="${CTX}/Dockerfile"
staged() { find "${CTX}" -maxdepth 1 -name '*.deb' -exec basename {} \; 2>/dev/null; }
staged_count() { staged | grep -c "$1" || true; }
# "tree deleted" must be distinguishable from "find failed": a bare find in a
# pipeline under pipefail kills the command substitution and truncates the run.
dockerfile_count() { # dockerfile_count <dir>
    if [ -d "$1" ]; then find "$1" -name Dockerfile 2>/dev/null | wc -l | tr -d ' '; else echo 0; fi
}
# Mode of the emitted Dockerfile (GNU stat on Linux, BSD stat on macOS). Git
# tracks only the exec bit, so no other check here can see a mode regression.
df_mode() { stat -c '%a' "${DF}" 2>/dev/null || stat -f '%Lp' "${DF}"; }
# Value of a single-quoted shell assignment in the emitted Dockerfile, for the
# Nth occurrence (1 = amd64 branch, 2 = arm64 branch).
df_val() { # df_val <var> <n>
    grep -oE "^ *$1='[^']*'" "${DF}" 2>/dev/null | sed -n "$2p" | sed "s/.*='//; s/'\$//"
}
# Package URL/SHA assignments that do not have exactly the safe shape
# `name='<no quote>'; \`. A value carrying a quote closes the assignment early
# and the rest of the line becomes shell that runs as root at docker build time,
# so the whole line, not the extracted value, is what has to be checked --
# extracting the value would read a payload's empty first field and see nothing
# wrong. Counting occurrences of the assignment cannot see this at all.
unsafe_assigns() {
    grep -E '^ *(asadm|server)(Url|Sha)=' "${DF}" 2>/dev/null |
        grep -cvE "^ *(asadm|server)(Url|Sha)='[^']*'; \\\\$" || true
}

scenario "promise 1/2: asadm staged from a local -u directory"
mk_pkgs "${WORK}/a" enterprise
mk_asadm "${WORK}/a"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" || true
check "both asadm arches staged" "asadm files" "$(staged_count asadm)" "2"
check "COPY emitted" "COPY *.deb present" \
    "$(grep -c '^COPY \*\.deb' "${DF}" || true)" "1"
check "emitted with the committed file mode" "Dockerfile mode" "$(df_mode)" "644"

scenario "promise 2 negative: --no-asadm stages none"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" --no-asadm || true
check "no asadm staged" "asadm files" "$(staged_count asadm)" "0"

scenario "promise 2 precedence: -A wins over an asadm in the -u dir"
mk_asadm "${WORK}/b" 9.9.9
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" -A "${WORK}/b" || true
check "-A beats -u" "staged asadm version" \
    "$(staged | grep -o '9\.9\.9' | head -1)" "9.9.9"
check "-u asadm not also staged" "5.0.3 files" "$(staged_count '5\.0\.3')" "0"

scenario "a local -u makes no outbound request, with or without an asadm in it"
mkdir -p "${WORK}/stub"
cat >"${WORK}/stub/curl" <<'STUB'
#!/bin/bash
for a in "$@"; do case "$a" in http*) echo "$a" >>"${CURL_LOG}" ;; esac; done
# CURL_FAIL_ONCE: drop the first request whose URL contains it, the way a reset
# connection or a firewall blackhole does -- exit 7, no HTTP status. Later
# requests for the same URL go through, which is what makes a retry observable.
if [ -n "${CURL_FAIL_ONCE:-}" ] && [ ! -e "${CURL_FAIL_MARK}" ]; then
    for a in "$@"; do
        case "$a" in
        *"${CURL_FAIL_ONCE}"*)
            : >"${CURL_FAIL_MARK}"
            exit 7
            ;;
        esac
    done
fi
exec /usr/bin/curl "$@"
STUB
chmod +x "${WORK}/stub/curl"
# -t runs the in-place update path and then bakes. The bake is not what these
# scenarios are about and needs a daemon CI does not have.
cat >"${WORK}/stub/docker" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "${WORK}/stub/docker"
CURL_LOG="${WORK}/curl.log"
export CURL_LOG
# The pinning case. A -u dir that already holds an asadm returned from the local
# branch even before the fix; only a dir with no asadm fell through to JFrog, so
# that is the input the zero-request promise has to be measured against.
mk_pkgs "${WORK}/noasadm" enterprise
: >"${CURL_LOG}"
PATH="${WORK}/stub:${PATH}" gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/noasadm" || true
check "zero http requests (no asadm in -u)" "urls fetched" \
    "$(wc -l <"${CURL_LOG}" | tr -d ' ')" "0"
check "warning names the -u path, not a host never contacted" "JFrog in warning" \
    "$(grep -c 'jfrog' "${CURRENT_LOG}" || true)" "0"
: >"${CURL_LOG}"
PATH="${WORK}/stub:${PATH}" gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" || true
check "zero http requests (asadm in -u)" "urls fetched" \
    "$(wc -l <"${CURL_LOG}" | tr -d ' ')" "0"

scenario "promise 5: a run that resolves nothing exits 1 and keeps releases/"
before=$(dockerfile_count "releases/${LINEAGE}")
mkdir -p "${WORK}/none/${VERSION}"
gen "${LINEAGE}" -u "${WORK}/none" && rc=0 || rc=$?
after=$(dockerfile_count "releases/${LINEAGE}")
check "exits 1" "exit code" "${rc}" "1"
check "releases/ intact" "Dockerfile count" "${after}" "${before}"

scenario "promise 6: a single -u file is not handed to the wrong target"
F="${WORK}/one/aerospike-server-enterprise_${VERSION}-1ubuntu24.04_amd64.deb"
mk_pkg "${F}"
gen "${VERSION}" -e enterprise -d ubuntu24.04 ubi10 -a amd64 -u "${F}" || true
check "deb target generated" "ubuntu24.04 staged deb" \
    "$(staged_count 'aerospike-server')" "1"
check "rpm target skipped" "ubi10 unchanged vs committed" \
    "$(git diff --quiet "releases/${LINEAGE}/enterprise/ubi10/" && echo untouched || echo regenerated)" "untouched"
check "no deb leaked into rpm target" "ubi10 staged packages" \
    "$(find "releases/${LINEAGE}/enterprise/ubi10" -maxdepth 1 \( -name '*.deb' -o -name '*.rpm' \) | wc -l | tr -d ' ')" "0"

# The single-file branch is a five-clause conjunction. Varying one clause at a
# time is the only way to tell which clauses are actually load-bearing; a suite
# that varies two proves nothing about either.
scenario "promise 6: each single-file clause is enforced on its own"
mk_pkg "${WORK}/neg/aerospike-server-enterprise_8.0.0.1-1ubuntu24.04_amd64.deb"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -a amd64 -u "${WORK}/neg/aerospike-server-enterprise_8.0.0.1-1ubuntu24.04_amd64.deb" || true
check "wrong version rejected" "staged packages" "$(staged_count 'aerospike-server')" "0"
git checkout -- releases/ 2>/dev/null || true
git clean -fdxq releases/ 2>/dev/null || true
mk_pkg "${WORK}/neg/aerospike-server-community_${VERSION}-1ubuntu24.04_amd64.deb"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -a amd64 -u "${WORK}/neg/aerospike-server-community_${VERSION}-1ubuntu24.04_amd64.deb" || true
check "wrong edition rejected" "staged packages" "$(staged_count 'aerospike-server')" "0"
git checkout -- releases/ 2>/dev/null || true
git clean -fdxq releases/ 2>/dev/null || true
mk_pkg "${WORK}/neg/aerospike-server-enterprise_${VERSION}-1ubuntu24.04_arm64.deb"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -a amd64 -u "${WORK}/neg/aerospike-server-enterprise_${VERSION}-1ubuntu24.04_arm64.deb" || true
check "wrong arch rejected" "staged packages" "$(staged_count 'aerospike-server')" "0"
git checkout -- releases/ 2>/dev/null || true
git clean -fdxq releases/ 2>/dev/null || true
mk_pkg "${WORK}/neg/aerospike-server-enterprise_${VERSION}-1ubuntu22.04_amd64.deb"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -a amd64 -u "${WORK}/neg/aerospike-server-enterprise_${VERSION}-1ubuntu22.04_amd64.deb" || true
check "wrong distro rejected" "staged packages" "$(staged_count 'aerospike-server')" "0"

# The fourth version component is a build number that reaches double digits, so
# a substring test picks 8.1.2.40 for a requested 8.1.2.4 and labels the image
# with the version it did not install.
scenario "a requested version is never satisfied by a longer one"
mk_pkg "${WORK}/coll/aerospike-server-enterprise_8.1.2.40-1ubuntu24.04_amd64.deb"
gen "8.1.2.4" -e enterprise -d ubuntu24.04 -a amd64 -u "${WORK}/coll" || true
check "8.1.2.40 not used for 8.1.2.4 (dir)" "staged packages" \
    "$(staged_count 'aerospike-server')" "0"
git checkout -- releases/ 2>/dev/null || true
git clean -fdxq releases/ 2>/dev/null || true
gen "8.1.2.4" -e enterprise -d ubuntu24.04 -a amd64 \
    -u "${WORK}/coll/aerospike-server-enterprise_8.1.2.40-1ubuntu24.04_amd64.deb" || true
check "8.1.2.40 not used for 8.1.2.4 (single file)" "staged packages" \
    "$(staged_count 'aerospike-server')" "0"

# find_local_asadm_package falls back past the distro-qualified tier. The
# fallback must not accept a package built for another distro.
scenario "an asadm built for another distro is never staged"
mk_pkgs "${WORK}/wrongdistro" enterprise
mk_asadm "${WORK}/wrongdistro" 5.0.3 ubuntu22.04
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/wrongdistro" || true
check "ubuntu22.04 asadm not staged into a ubuntu24.04 image" "asadm files" \
    "$(staged_count asadm)" "0"
check "server still staged" "server files" "$(staged_count 'aerospike-server')" "2"
# A package naming no distro at all is hand-built and stays usable.
git checkout -- releases/ 2>/dev/null || true
git clean -fdxq releases/ 2>/dev/null || true
mk_pkgs "${WORK}/nodistro" enterprise
mk_pkg "${WORK}/nodistro/aerospike-asadm_5.0.3_x86_64.deb"
mk_pkg "${WORK}/nodistro/aerospike-asadm_5.0.3_aarch64.deb"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/nodistro" || true
check "distro-less asadm still staged" "asadm files" "$(staged_count asadm)" "2"

# --- Remote fixtures ---------------------------------------------------------
# Rooted at /artifactory/database-deb-prod-public-local so is_artifactory_url
# matches and artifactory_pkg_dir's apt pool/<suite>/ mapping is exercised. A
# plain-HTTP root takes the directory-index branch and leaves the JFrog
# resolution this PR is named for untested.
REPO_ROOT="${WORK}/repo/artifactory/database-deb-prod-public-local"
POOL="${REPO_ROOT}/pool/noble/aerospike-asadm"
mk_pkg "${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb"
mk_pkg "${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb"
AMD_SHA=$(sha_of "${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb")
ARM_SHA=$(sha_of "${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb")
# Distinct contents, so an arch mix-up changes the digest. Identical zero-byte
# files would hash the same and the per-arch assertion would prove nothing.
printf 'amd64' >"${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb"
printf 'arm64' >"${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb"
AMD_SHA=$(sha_of "${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb")
ARM_SHA=$(sha_of "${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb")
echo "${AMD_SHA}" >"${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb.sha256"
echo "${ARM_SHA}" >"${POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb.sha256"

# A pool with no sidecars and no digest header: the unbuildable combination.
NOSHA_POOL="${WORK}/repo/artifactory/database-deb-prod-public-local-nosha/pool/noble/aerospike-asadm"
mkdir -p "${NOSHA_POOL}"
: >"${NOSHA_POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb"
: >"${NOSHA_POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb"

# A pool whose sidecar is not a digest at all.
BADSHA_POOL="${WORK}/repo/artifactory/database-deb-prod-public-local-badsha/pool/noble/aerospike-asadm"
mkdir -p "${BADSHA_POOL}"
: >"${BADSHA_POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb"
: >"${BADSHA_POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb"
printf "%s" "';touch ${WORK}/pwned;:'" \
    >"${BADSHA_POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb.sha256"
printf "%s" "';touch ${WORK}/pwned;:'" \
    >"${BADSHA_POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb.sha256"

# A crafted index entry that would break out of the single-quoted assignment.
# A hand-written index.html, not the autoindex: python percent-encodes hrefs,
# so a raw quote never survives a generated listing and the fixture would prove
# nothing. JFrog serves the name as written.
#
# The entry resolves completely -- the file and its sidecar exist under the
# payload name -- so removing the charset filter puts the payload in the
# Dockerfile and the assertions below fail on the injection itself. Without
# them the entry would 404 on its checksum and be dropped, and the suite would
# be pinning the checksum gate while appearing to pin the filter.
# The payload carries no "/" so it can be a filename.
INJ_POOL="${WORK}/repo/artifactory/database-deb-prod-public-local-inj/pool/noble/aerospike-asadm"
mkdir -p "${INJ_POOL}"
mk_pkg "${INJ_POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb"
mk_pkg "${INJ_POOL}/aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb"
INJ_NAME="aerospike-asadm_9.9.9-1ubuntu24.04'\$(id)'_amd64.deb"
mk_pkg "${INJ_POOL}/${INJ_NAME}"
cat >"${INJ_POOL}/index.html" <<IDX
<html><body>
<a href="aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb">a</a>
<a href="aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb">b</a>
<a href="${INJ_NAME}">c</a>
</body></html>
IDX

# Started without a wrapping subshell so \$! is python's own pid -- otherwise
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
BASE="http://127.0.0.1:${PORT}/artifactory/database-deb-prod-public-local"

scenario "remote JFrog resolution: apt pool layout, per-arch URL and checksum"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" -A "${BASE}" || true
check "resolved through the apt pool/<suite>/ mapping" "pool/noble in asadmUrl" \
    "$(grep -c "asadmUrl='http://[^']*/pool/noble/aerospike-asadm/" "${DF}" || true)" "2"
# Counting occurrences cannot see an arch mix-up, which is the failure the
# per-arch resolution was added to prevent. Assert the values.
check "amd64 branch gets the amd64 package" "asadmUrl #1" \
    "$(basename "$(df_val asadmUrl 1)")" "aerospike-asadm_5.0.3-1ubuntu24.04_x86_64.deb"
check "arm64 branch gets the arm64 package" "asadmUrl #2" \
    "$(basename "$(df_val asadmUrl 2)")" "aerospike-asadm_5.0.3-1ubuntu24.04_aarch64.deb"
check "amd64 checksum matches its package" "asadmSha #1" "$(df_val asadmSha 1)" "${AMD_SHA}"
check "arm64 checksum matches its package" "asadmSha #2" "$(df_val asadmSha 2)" "${ARM_SHA}"
check_ne "the two arches do not share a digest" "asadmSha" "${AMD_SHA}" "${ARM_SHA}"

scenario "a URL is never emitted next to an empty checksum"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" -A "${BASE}-nosha" || true
# `echo "" */tmp/x.deb | sha256sum --strict --check -` exits 1, which is fatal
# under the generated SHELL. An unresolvable checksum must drop the package,
# not ship a Dockerfile that cannot build.
check "no asadm URL emitted" "asadmUrl count" \
    "$(grep -c "asadmUrl='http" "${DF}" || true)" "0"
check "no live URL beside an empty digest" "url-with-empty-sha pairs" \
    "$(grep -A1 "asadmUrl='http" "${DF}" 2>/dev/null | grep -c "asadmSha=''" || true)" "0"
check "server still builds" "serverUrl or staged package" \
    "$(staged_count 'aerospike-server')" "2"

scenario "a malformed checksum is dropped, not substituted"
rm -f "${WORK}/pwned"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" -A "${BASE}-badsha" || true
check "payload never reaches the Dockerfile" "assignments that break their quoting" \
    "$(unsafe_assigns)" "0"
check "amd64 checksum left empty" "asadmSha #1" "$(df_val asadmSha 1)" ""
check "arm64 checksum left empty" "asadmSha #2" "$(df_val asadmSha 2)" ""
check "asadm dropped rather than emitted unchecked" "asadmUrl count" \
    "$(grep -c "asadmUrl='http" "${DF}" || true)" "0"
check "malformed checksum reported" "warning present" \
    "$(grep -c 'malformed SHA256' "${CURRENT_LOG}" || true)" "2"

scenario "an injected index entry is rejected at the boundary"
rm -f "${WORK}/pwned"
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" -A "${BASE}-inj" || true
check "injected entry not selected" "9.9.9 present" \
    "$(grep -c '9\.9\.9' "${DF}" || true)" "0"
check "no quote escaped into the Dockerfile" "assignments that break their quoting" \
    "$(unsafe_assigns)" "0"
# The old check for the payload's side effect was a tautology: the injected
# $(...) only runs at docker build time and this suite never builds, so it
# reported ok even while the payload sat in the Dockerfile. Assert that the
# generated shell text cannot execute anything instead -- and that the entries
# either side of the injected one still resolved, so a resolver that rejected
# everything cannot pass this scenario.
check "no command substitution anywhere in the emitted asadm text" "\$( in asadm lines" \
    "$(grep -cE "^ *asadm(Url|Sha)=.*\\\$\\(" "${DF}" || true)" "0"
check "legitimate entries still resolved" "asadmUrl count" \
    "$(grep -c "asadmUrl='http" "${DF}" || true)" "2"

scenario "stale packages are purged from a target before it is rewritten"
# No reset between the two runs: the point is that the second generation clears
# what the first staged. COPY *.deb takes everything in the directory, so a
# leftover package from an earlier version is installed alongside the new one.
mk_pkgs "${WORK}/old" enterprise
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/old" || true
check "first run staged its packages" "server files" "$(staged_count 'aerospike-server')" "2"
OLDV="8.1.2.4"
mk_pkg "${WORK}/new/aerospike-server-enterprise_${OLDV}-1ubuntu24.04_amd64.deb"
mk_pkg "${WORK}/new/aerospike-server-enterprise_${OLDV}-1ubuntu24.04_arm64.deb"
gen "${OLDV}" -e enterprise -d ubuntu24.04 -u "${WORK}/new" || true
check "previous version's packages purged" "8.1.3.0 files left" \
    "$(staged_count "${VERSION}")" "0"
check "new version's packages staged" "8.1.2.4 files" "$(staged_count "${OLDV}")" "2"

scenario "an incomplete Dockerfile is never written over a committed one"
# Run against a copy of the tree with the footer fragment emptied, so generation
# produces a Dockerfile with no ENTRYPOINT/CMD. The validation must reject it
# before it replaces the committed file -- the emitted file is built in a temp
# location and moved into place only after it validates.
BROKEN="${WORK}/broken"
mkdir -p "${BROKEN}"
tar -cf - --exclude=.git --exclude='*.snyk' . 2>/dev/null | tar -xf - -C "${BROKEN}"
: >"${BROKEN}/lib/dockerfile_fragment_footer.docker"
cp "${DF}" "${WORK}/committed.Dockerfile"
(cd "${BROKEN}" && ./docker-build.sh -g "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/a" \
    >"${CURRENT_LOG}" 2>&1) && brc=0 || brc=$?
check "run fails" "exit code" "${brc}" "1"
check "incomplete Dockerfile reported" "warning present" \
    "$(grep -c 'incomplete Dockerfile' "${CURRENT_LOG}" || true)" "1"
check "committed Dockerfile untouched" "diff vs committed" \
    "$(cmp -s "${BROKEN}/${DF}" "${WORK}/committed.Dockerfile" && echo same || echo replaced)" "same"

scenario "the bake file omits targets this run did not generate"
# generate_bake selects by directory existence and tags with the version
# resolved this run, so a target left with its committed Dockerfile would be
# published under the new version's tags carrying the previous build's contents.
cat >"${WORK}/stub/docker" <<'DSTUB'
#!/bin/bash
exit 0
DSTUB
chmod +x "${WORK}/stub/docker"
# ubi10 needs an rpm; the -u dir holds only debs, so it cannot resolve and is
# skipped while ubuntu24.04 succeeds.
PATH="${WORK}/stub:${PATH}" ./docker-build.sh -g -t "${VERSION}" -e enterprise \
    -d ubuntu24.04 ubi10 -u "${WORK}/a" >"${CURRENT_LOG}" 2>&1 || true
check "bake file written" "bake-multi.hcl exists" \
    "$(test -f bake-multi.hcl && echo yes || echo no)" "yes"
check "generated target present" "ubuntu24.04 in bake file" \
    "$(grep -q 'releases/8.1/enterprise/ubuntu24.04' bake-multi.hcl && echo present || echo absent)" "present"
check "skipped target omitted" "ubi10 in bake file" \
    "$(grep -q 'releases/8.1/enterprise/ubi10' bake-multi.hcl && echo present || echo absent)" "absent"
check "omission reported" "warning present" \
    "$(grep -c 'Omitting releases/8.1/enterprise/ubi10' "${CURRENT_LOG}" || true)" "1"
rm -f bake-multi.hcl

scenario "a 404 asadm source is absent, not an error"
# Promise 3's case: the package is authoritatively not published, so the image
# is built without it and the run succeeds.
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/noasadm" \
    -A "${BASE}-nosuchrepo" && rc404=0 || rc404=$?
check "run succeeds" "exit code" "${rc404}" "0"
check "target still generated" "server files" "$(staged_count 'aerospike-server')" "2"
check "no asadm staged" "asadm files" "$(staged_count asadm)" "0"

scenario "an unreadable -A fails the target instead of dropping asadm"
# A source the user named explicitly either yields a package or says why not.
# A closed port gives curl no HTTP status at all, which is the case that used to
# be indistinguishable from "not published yet".
DEADPORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
gen "${VERSION}" -e enterprise -d ubuntu24.04 -u "${WORK}/noasadm" \
    -A "http://127.0.0.1:${DEADPORT}/artifactory/database-deb-prod-public-local" && rcA=0 || rcA=$?
check "run fails" "exit code" "${rcA}" "1"
check "reported as unreadable, not absent" "warning present" \
    "$(grep -q 'could not be read' "${CURRENT_LOG}" && echo yes || echo no)" "yes"
check "not reported as merely absent" "\"will have none\" warning" \
    "$(grep -c 'will have none' "${CURRENT_LOG}" || true)" "0"
check "nothing staged into the target" "server files" "$(staged_count 'aerospike-server')" "0"

scenario "an unreadable server source aborts instead of dropping a lineage"
# The partial-release path: on an all-lineages run a dropped lineage leaves the
# survivors' count non-zero, so the run would reach bake a lineage short.
gen -e enterprise -d ubuntu24.04 \
    -u "http://127.0.0.1:${DEADPORT}/artifactory/database-deb-prod-public-local" && rcU=0 || rcU=$?
check "run fails" "exit code" "${rcU}" "1"
check "refuses rather than continuing" "warning present" \
    "$(grep -q 'could not be read' "${CURRENT_LOG}" && echo yes || echo no)" "yes"
check "releases/ intact" "Dockerfile count" \
    "$(dockerfile_count "releases/${LINEAGE}")" "$(git ls-files "releases/${LINEAGE}" | grep -c Dockerfile)"

scenario "a pre-release version resolves through the loose pattern"
# The exact pattern requires <version>-<rev>; a pre-release string
# (8.1.1.0-start-16-g216a75438) only matches the looser second pattern. Both are
# now tried against one listing, so a regression that keeps only the first
# pattern would silently stop resolving these.
# -rc2 rather than -1ubuntu24.04: the exact pattern requires a numeric revision
# followed by the distro, so this filename is reachable only through the loose
# one. A fixture that also matched the exact pattern would prove nothing.
PRE="8.1.1.0-start-16-g216a75438"
PRE_POOL="${WORK}/repo/artifactory/database-deb-prod-public-local-pre/pool/noble/aerospike-server-enterprise"
mk_pkg "${PRE_POOL}/aerospike-server-enterprise_${PRE}-rc2_amd64.deb"
mk_pkg "${PRE_POOL}/aerospike-server-enterprise_${PRE}-rc2_arm64.deb"
gen "${PRE}" -e enterprise -d ubuntu24.04 -u "${BASE}-pre" --no-asadm || true
check "pre-release server resolved" "serverUrl count" \
    "$(grep -c "serverUrl='http" "${DF}" || true)" "2"
check "resolved the pre-release build" "version in serverUrl" \
    "$(grep -c "serverUrl='http[^']*${PRE}" "${DF}" || true)" "2"

scenario "each directory listing is fetched once per run"
# Two arches times the exact/loose retry re-fetched one arch-independent pool
# URL four times. The patterns now share a listing and the listing is cached for
# the run, so the same directory is requested once.
: >"${CURL_LOG}"
PATH="${WORK}/stub:${PATH}" gen "${VERSION}" -e enterprise -d ubuntu24.04 \
    -u "${WORK}/a" -A "${BASE}" || true
check "asadm pool listed exactly once" "listing requests" \
    "$(grep -c "database-deb-prod-public-local/pool/noble/aerospike-asadm/\$" "${CURL_LOG}" || true)" "1"
check "still resolved both arches" "asadmUrl count" \
    "$(grep -c "asadmUrl='http" "${DF}" || true)" "2"

# A repo carrying server packages for every lineage that ships ubuntu24.04, plus
# an asadm pool. Both pool URLs are lineage-independent, so an all-lineages run
# reads each of them once per lineage -- the only shape in which a cached
# listing outcome is reused rather than recomputed.
MULTI="${WORK}/repo/artifactory/database-deb-prod-public-local-multi"
for v in 7.2.0.21 8.0.0.19 "${VERSION}"; do
    mk_pkg "${MULTI}/pool/noble/aerospike-server-enterprise/aerospike-server-enterprise_${v}-4ubuntu24.04_amd64.deb"
    mk_pkg "${MULTI}/pool/noble/aerospike-server-enterprise/aerospike-server-enterprise_${v}-4ubuntu24.04_arm64.deb"
done
mk_asadm "${MULTI}/pool/noble/aerospike-asadm"

scenario "the default in-place update path resolves a native package"
# Every scenario above runs -g. The in-place update path -- no -g, the default
# mode, and the one the README's JFrog example uses -- calls resolve_packages as
# a plain statement rather than as an if-condition, so errexit is live there. A
# successful native resolution that returns non-zero kills the whole run before
# anything is written and without a log line, which is exactly what a bare
# `return` after a false `[ ]` test produced.
: >"${CURL_LOG}"
PATH="${WORK}/stub:${PATH}" ./docker-build.sh -t "${LINEAGE}" -e enterprise -d ubuntu24.04 \
    -u "${BASE}-multi" --no-asadm >"${CURRENT_LOG}" 2>&1 && rcU2=0 || rcU2=$?
check "run survives resolution" "exit code" "${rcU2}" "0"
check "reaches the generation step" "log line" \
    "$(grep -qF 'Dockerfiles generated in releases/' "${CURRENT_LOG}" && echo yes || echo no)" "yes"
check "server resolved into the updated Dockerfile" "serverUrl count" \
    "$(grep -c "serverUrl='http" "${DF}" || true)" "2"
check "resolved the discovered build revision" "revision in serverUrl" \
    "$(grep -c "serverUrl='http[^']*${VERSION}-4ubuntu24.04" "${DF}" || true)" "2"

scenario "a transient listing failure is retried, not cached as an error"
# ${code:-000} was cached like any other outcome, so one dropped connection --
# a DNS blip, a TLS reset, a firewall that blackholes rather than refuses --
# became a permanent AS_LIST_ERROR for that URL for the rest of the run. Every
# later lineage read the poisoned entry instead of the repo, and because an
# explicitly named -A source must either yield a package or fail its target,
# a single blip on the first lineage failed all of them. Only 200 and 404 are
# answers; anything else is cached nowhere and re-probed.
: >"${CURL_LOG}"
rm -f "${WORK}/curlmark"
CURL_FAIL_ONCE="pool/noble/aerospike-asadm" CURL_FAIL_MARK="${WORK}/curlmark" \
    PATH="${WORK}/stub:${PATH}" gen -e enterprise -d ubuntu24.04 \
    -u "${BASE}-multi" -A "${BASE}-multi" && rcT=0 || rcT=$?
check "the blip does not fail the run" "exit code" "${rcT}" "0"
check "the failed listing is re-probed" "asadm pool requests" \
    "$(grep -c "database-deb-prod-public-local-multi/pool/noble/aerospike-asadm/\$" "${CURL_LOG}" || true)" "2"
check "the lineage that hit the blip has no asadm" "7.2 asadmUrl count" \
    "$(grep -c "asadmUrl='http" "releases/7.2/enterprise/ubuntu24.04/Dockerfile" || true)" "0"
check "a later lineage recovers on the retry" "8.0 asadmUrl count" \
    "$(grep -c "asadmUrl='http" "releases/8.0/enterprise/ubuntu24.04/Dockerfile" || true)" "2"
check "and so does the next" "${LINEAGE} asadmUrl count" \
    "$(grep -c "asadmUrl='http" "${DF}" || true)" "2"

scenario "a new lineage builds for its own distros, and an unknown one is refused"
# 8.2 is not published yet, so nothing else in this suite -- or in CI, which
# discovers lineages from releases/ -- exercises it. This pins the support_distros
# entry that a targeted `-g 8.2` needs, ahead of the packages landing.
#
# The unknown-lineage half matters more than it looks: support_distros is also
# what generate.sh prunes releases/ with, so the old "fall back to 7.1's distros"
# answer meant a -g of an unlisted lineage would rm -rf the distro directories it
# actually ships and keep ones its packages were never built for.
NEW_LINEAGE="8.2"
NEW_VERSION="8.2.0.0"
L82="${WORK}/repo/artifactory/database-deb-prod-public-local-82/pool/noble"
for ed in community enterprise federal; do
    mk_pkg "${L82}/aerospike-server-${ed}/aerospike-server-${ed}_${NEW_VERSION}-3ubuntu24.04_amd64.deb"
    mk_pkg "${L82}/aerospike-server-${ed}/aerospike-server-${ed}_${NEW_VERSION}-3ubuntu24.04_arm64.deb"
done
gen "${NEW_LINEAGE}" -u "${BASE}-82" --no-asadm && rc82=0 || rc82=$?
check "the new lineage generates" "exit code" "${rc82}" "0"
# Three, not six: the fixture is a deb-only repo, so the two rpm targets per
# edition resolve nothing and are skipped. A count over the whole lineage rather
# than over ubuntu24.04 alone therefore also pins that no ubi tree was written.
check "one Dockerfile per edition, no ubi tree" "Dockerfiles under the lineage" \
    "$(dockerfile_count "releases/${NEW_LINEAGE}")" "3"
check "it resolves the discovered version" "serverUrl" \
    "$(grep -c "serverUrl='http[^']*${NEW_VERSION}-3ubuntu24.04" \
        "releases/${NEW_LINEAGE}/enterprise/ubuntu24.04/Dockerfile" || true)" "2"
# ubi10, not ubi9: an 8.2 that silently inherited the fallback would build the
# wrong UBI, and against a deb-only repo both are skipped, so the emitted tree
# cannot tell them apart. The pruning list is where the difference shows.
check "it is mapped to ubi10, not the fallback's ubi9" "support_distros ${NEW_LINEAGE}" \
    "$(bash -c 'source lib/log.sh; source lib/support.sh; support_distros "$1"' _ "${NEW_LINEAGE}")" \
    "ubuntu24.04 ubi10"
gen "9.9" -u "${BASE}-82" --no-asadm && rc99=0 || rc99=$?
check "an unknown lineage fails" "exit code" "${rc99}" "1"
check "and says why" "warning present" \
    "$(grep -q 'unsupported release lineage' "${CURRENT_LOG}" && echo yes || echo no)" "yes"
# The tracked tree, not a total: releases/8.2 is untracked and still on disk from
# the half of this scenario above, so a count would compare the wrong things.
check "no committed Dockerfile was deleted" "tracked deletions under releases/" \
    "$(git status --porcelain -- releases/ | grep -c '^ D' || true)" "0"

echo
if [ "${SCENARIOS}" -ne "${EXPECTED_SCENARIOS}" ]; then
    # A scenario that aborts mid-run is otherwise indistinguishable from a
    # complete pass: the remaining checks simply never report.
    echo "INCOMPLETE: ran ${SCENARIOS} of ${EXPECTED_SCENARIOS} scenarios."
    exit 1
fi
if [ "${FAILED}" -eq 0 ]; then
    echo "All generation tests passed (${SCENARIOS} scenarios)."
else
    echo "${FAILED} generation test(s) failed."
    exit 1
fi
