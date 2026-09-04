#!/usr/bin/env bash
# Version utilities for Aerospike Docker images.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/fetch.sh (callers must also source lib/log.sh if using fetch with DEBUG).
#
# Supported version formats:
#   - 8.1.1.0                      (release)
#   - 8.1.1.0-rc2                  (release candidate)
#   - 8.1.1.0-start-16             (development build)
#   - 8.1.1.0-start-16-gea126d3    (development build with git hash)

set -Eeuo pipefail

source lib/fetch.sh

ARTIFACTS_DOMAIN=${ARTIFACTS_DOMAIN:="https://download.aerospike.com/artifacts"}

# Source for the standalone aerospike-asadm package, independent of
# ARTIFACTS_DOMAIN because the download.aerospike.com artifact tree does not
# carry asadm on its own (it ships inside aerospike-tools there).
# ASADM_DOMAIN (-A/--asadm-url) overrides both pkg-type defaults when set.
ASADM_DOMAIN_DEB=${ASADM_DOMAIN_DEB:="https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local"}
ASADM_DOMAIN_RPM=${ASADM_DOMAIN_RPM:="https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local"}
ASADM_DOMAIN=${ASADM_DOMAIN:=""}
ASADM_DISABLED=${ASADM_DISABLED:=false}

# Extract lineage (major.minor) from a full version string (e.g. 8.1.1.0 -> 8.1).
function get_lineage_from_version() {
    echo "$1" | grep -oE '^[0-9]+\.[0-9]+'
}

# Check if URL is a direct edition URL (contains aerospike-server-<edition>)
function is_direct_url() {
    [[ "${ARTIFACTS_DOMAIN}" =~ aerospike-server-(community|enterprise|federal) ]]
}

# Check if URL is a JFrog Artifactory repo. Two layouts, keyed off pkg type:
#   rpm: base/el9/x86_64/pkg.rpm          (flat, one dir per distro/arch)
#   deb: base/pool/noble/<pkg>/pkg.deb    (apt repo: dists/ + pool/)
function is_artifactory_url() {
    [[ "$1" =~ jfrog\.io|artifactory|/database-rpm-|/database-deb- ]]
}

function is_artifactory_repo() {
    is_artifactory_url "${ARTIFACTS_DOMAIN}"
}

# Resolve the asadm source for a package type: -A/--asadm-url when given,
# otherwise the JFrog repo matching the package format.
function asadm_domain_for_pkg_type() {
    if [ -n "${ASADM_DOMAIN}" ]; then
        echo "${ASADM_DOMAIN}"
    elif [ "$1" = "deb" ]; then
        echo "${ASADM_DOMAIN_DEB}"
    else
        echo "${ASADM_DOMAIN_RPM}"
    fi
}

# The source get_asadm_package_link_native actually searched, for reporting.
# It takes the local -u branch before consulting asadm_domain_for_pkg_type, so
# using that function alone names a JFrog host the run never contacted -- which
# is every local native build, since asadm is not published there yet. The
# precedence lives here, beside the resolver that implements it.
function asadm_source_for_pkg_type() {
    if [ -z "${ASADM_DOMAIN}" ] && is_local_artifacts_dir; then
        echo "${ARTIFACTS_DOMAIN}"
    else
        asadm_domain_for_pkg_type "$1"
    fi
}

# Check if -u points to a local directory (not http/https)
function is_local_artifacts_dir() {
    [[ "${ARTIFACTS_DOMAIN}" != http* ]]
}

# Escape ERE metacharacters so a literal string can be used inside a pattern.
function _ere_quote() {
    printf '%s' "$1" | sed 's/[][^$.*+?(){}|\\]/\\&/g'
}

# True when a package filename names the given arch, under either spelling
# (amd64/x86_64, arm64/aarch64), or is arch-independent. Both spellings are
# accepted because Aerospike publishes asadm debs as _aarch64.deb while the
# server debs use the dpkg _arm64.deb. The container-side counterparts are the
# ALT_ARCH globs in scripts/{deb,rpm}/install-native.sh; keep all three in step.
function pkg_name_matches_arch() {
    local name=$1 arch=$2
    local deb_arch="${arch}"
    [ "${arch}" = "x86_64" ] && deb_arch="amd64"
    [ "${arch}" = "aarch64" ] && deb_arch="arm64"

    name=$(basename "${name}")
    case "${name}" in
    *"${arch}"* | *"${deb_arch}"* | *_all.deb | *.noarch.rpm) return 0 ;;
    esac
    return 1
}

# True when a package filename carries exactly the given version, not merely a
# string containing it. A plain substring test accepts 8.1.2.40 for a requested
# 8.1.2.4 -- the fourth component is a build number that routinely reaches
# double digits -- producing an image labelled and tagged with the wrong
# version. The version must be delimited on both sides: preceded by -, _ or .,
# and followed by anything that cannot continue the number.
function pkg_name_matches_version() {
    local name version_re
    name=$(basename "$1")
    version_re="[-_.]$(_ere_quote "$2")([^0-9.]|\.[^0-9]|$)"
    [[ "${name}" =~ ${version_re} ]]
}

# True when a package filename names any distro this tool knows how to build
# for. Used to tell a hand-named, distro-less package (safe to use anywhere)
# from one built for a different distro (never safe). The list is derived from
# support_distro_to_artifact_name so adding a distro does not need a second
# edit here.
function pkg_name_names_a_distro() {
    local name d
    name=$(basename "$1")
    for d in $(support_artifact_distros); do
        [[ "${name}" == *"${d}"* ]] && return 0
    done
    return 1
}

# Newest path from a newline-separated list, keeping only names that carry
# exactly the given version. The find globs above are substring matches, so
# without this a directory holding both 8.1.2.4 and 8.1.2.40 resolves to the
# latter -- disagreeing with the single-file branch about the same packages.
function _pick_versioned() {
    local version=$1 paths=$2 f out=""
    while IFS= read -r f; do
        [ -n "${f}" ] || continue
        pkg_name_matches_version "${f}" "${version}" && out+="${f}"$'\n'
    done <<<"${paths}"
    printf '%s' "${out}" | grep -vE '^$' | sort -V | tail -1 || true
}

# Outcome of a directory listing, as the exit status of artifactory_list_names
# and everything built on it. "Empty" is not an outcome: an empty listing with
# status OK means the directory exists and holds nothing, which is a different
# fact from "the host refused us" and has to stay distinguishable all the way
# up to the caller that decides whether to skip or abort.
readonly AS_LIST_OK=0
readonly AS_LIST_ABSENT=1 # 404 -- authoritatively not there
readonly AS_LIST_ERROR=2  # 000/401/403/5xx -- we do not know

# List the entry names in an Artifactory directory index (HTML autoindex).
#
# Entries are constrained to the package-filename charset. A name is later
# concatenated into a URL that is substituted into a single-quoted shell
# assignment in the generated Dockerfile, so a name containing a quote,
# "$", "(" or a backtick would break out of the quoting and execute at
# docker build time. The index is attacker-controlled over plain HTTP, so
# the charset is enforced here, at the boundary, rather than at each use.
#
# The HTTP status is captured rather than discarded. Collapsing 404, 403, DNS
# failure, TLS failure and connect timeout into one empty string made "not
# published yet" indistinguishable from "your -A is wrong" -- and, one level up,
# let a single timed-out listing drop a lineage from a release at exit 0.
# Measured against the live repos: an unreadable repo answers 401 and a
# nonexistent one 404, so anything that is not 200 or 404 is an error.
function artifactory_list_names() {
    local dir_url=$1
    [ -z "${dir_url}" ] && return "${AS_LIST_ABSENT}"

    local cached body code
    cached=$(_list_cache_path "${dir_url}")
    if [ -n "${cached}" ] && [ -f "${cached}" ]; then
        code=$(head -1 "${cached}")
        tail -n +2 "${cached}"
        [ "${code}" = "200" ] && return "${AS_LIST_OK}"
        [ "${code}" = "404" ] && return "${AS_LIST_ABSENT}"
        return "${AS_LIST_ERROR}"
    fi

    # -w appends the status as a final line; --fail is deliberately not used, so
    # a 404 body is discarded but its status still reaches us.
    local raw
    raw=$(curl -sSL -w '\n%{http_code}' "${dir_url}/" 2>/dev/null || true)
    code=$(printf '%s' "${raw}" | tail -1)
    body=$(printf '%s' "${raw}" | sed '$d')
    log_debug "list - ${dir_url}/ (${code:-000})"

    local names=""
    if [ "${code}" = "200" ]; then
        names=$(printf '%s\n' "${body}" |
            grep -oE 'href="[^"?][^"]*"' | sed 's/^href="//; s/"$//' |
            grep -E '^[A-Za-z0-9][A-Za-z0-9._+~:-]*/?$' |
            grep -vE '^\.\.?/?$' || true)
    fi
    if [ -n "${cached}" ]; then
        # A 404 is the result most worth caching: the miss path re-probes it for
        # every arch and every pattern.
        printf '%s\n%s\n' "${code:-000}" "${names}" >"${cached}" 2>/dev/null || true
    fi
    printf '%s\n' "${names}"

    [ "${code}" = "200" ] && return "${AS_LIST_OK}"
    [ "${code}" = "404" ] && return "${AS_LIST_ABSENT}"
    return "${AS_LIST_ERROR}"
}

# Cache file for one directory URL, or empty when caching is off.
#
# A directory listing does not change within one docker-build.sh run, and the
# same URL is fetched once per arch times once per pattern -- 4x for a single
# target, ~390 requests for a full -g against a JFrog repo. An in-memory
# `declare -gA` cache cannot work here: every reader is inside $( ), so the
# writes die with the subshell. A file survives it. AS_LIST_CACHE_DIR is created
# and removed by docker-build.sh, so the cache never outlives the run that
# built it -- a long -p that spans a JFrog publish still sees one consistent
# snapshot rather than a stale one from an earlier invocation.
function _list_cache_path() {
    [ -n "${AS_LIST_CACHE_DIR:-}" ] && [ -d "${AS_LIST_CACHE_DIR}" ] || {
        echo ""
        return
    }
    local key
    key=$(printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -c1-40) ||
        key=$(printf '%s' "$1" | sha256sum | cut -c1-40)
    echo "${AS_LIST_CACHE_DIR}/${key}"
}

# Directory holding native packages for one package name in a JFrog repo.
#   deb: <base>/pool/<suite>/<pkg_name>   (apt repo: dists/ + pool/ layout)
#   rpm: <base>/<artifact_distro>/<arch>  (flat yum repo)
function artifactory_pkg_dir() {
    local base_url=$1 artifact_distro=$2 arch=$3 pkg_type=$4 pkg_name=$5

    if [ "${pkg_type}" = "deb" ]; then
        local suite
        suite=$(support_distro_to_apt_suite "${artifact_distro}")
        [ -z "${suite}" ] && {
            echo ""
            return
        }
        echo "${base_url}/pool/${suite}/${pkg_name}"
    else
        echo "${base_url}/${artifact_distro}/${arch}"
    fi
}

# Echo the URL of the highest-versioned file in an Artifactory directory whose
# name matches an ERE. Empty when the directory or a match is absent; exit
# status carries which, and AS_LIST_ERROR when the listing could not be read.
#
# The listing is captured before it is filtered. Piping straight out of
# artifactory_list_names discards its exit status, which is the whole point of
# having one.
function artifactory_pick_latest() {
    local dir_url=$1 pattern=$2
    local name names rc=0
    [ -z "${dir_url}" ] && {
        echo ""
        return "${AS_LIST_ABSENT}"
    }
    names=$(artifactory_list_names "${dir_url}") || rc=$?
    if [ "${rc}" -eq "${AS_LIST_ERROR}" ]; then
        echo ""
        return "${AS_LIST_ERROR}"
    fi
    name=$(printf '%s\n' "${names}" | grep -E "${pattern}" | sort -V | tail -1 || true)
    [ -z "${name}" ] && {
        echo ""
        return "${AS_LIST_ABSENT}"
    }
    echo "${dir_url}/${name}"
}

# Like artifactory_pick_latest, but the arch is matched against the filename
# under either spelling rather than being baked into the pattern, and several
# patterns may be given: the first that matches anything wins.
#
# Taking a pattern list rather than being called once per pattern is what lets
# the exact-then-loose retry share a single listing instead of re-fetching the
# same directory for each.
function artifactory_pick_latest_for_arch() {
    local dir_url=$1 arch=$2
    shift 2
    local name names pattern rc=0
    [ -z "${dir_url}" ] && {
        echo ""
        return "${AS_LIST_ABSENT}"
    }
    names=$(artifactory_list_names "${dir_url}") || rc=$?
    if [ "${rc}" -eq "${AS_LIST_ERROR}" ]; then
        echo ""
        return "${AS_LIST_ERROR}"
    fi
    for pattern in "$@"; do
        name=$(printf '%s\n' "${names}" | grep -E "${pattern}" |
            while read -r n; do
                pkg_name_matches_arch "${n}" "${arch}" && echo "${n}"
            done | sort -V | tail -1 || true)
        if [ -n "${name}" ]; then
            echo "${dir_url}/${name}"
            return "${AS_LIST_OK}"
        fi
    done
    echo ""
    return "${AS_LIST_ABSENT}"
}

# The package type a JFrog repo holds, inferred from its URL, or empty when the
# URL does not say. The two published repos are single-format.
function artifactory_repo_pkg_type() {
    case "$1" in
    *database-deb-*) echo "deb" ;;
    *database-rpm-*) echo "rpm" ;;
    *) echo "" ;;
    esac
}

# Discover the latest version for a lineage in a JFrog repo by listing the
# enterprise package directory for each distro the lineage supports.
#
# Returns AS_LIST_ERROR when a listing could not be read, so the caller can tell
# "this lineage is not published" from "we could not find out" -- the second
# must not silently drop a lineage from a release.
function find_latest_version_for_lineage_artifactory() {
    local lineage=$1
    local lineage_re repo_type
    lineage_re=$(_ere_quote "${lineage}")
    repo_type=$(artifactory_repo_pkg_type "${ARTIFACTS_DOMAIN}")

    local versions="" distro artifact_distro pkg_type dir names rc=0 failed=false
    # shellcheck disable=SC2086
    for distro in $(support_distros "${lineage}"); do
        pkg_type=$(support_distro_to_pkg_type "${distro}")
        # A deb repo cannot hold el9 rpms. Probing it anyway is a guaranteed
        # 404 per rpm distro, on the discovery path every run takes.
        [ -n "${repo_type}" ] && [ "${pkg_type}" != "${repo_type}" ] && continue
        artifact_distro=$(support_distro_to_artifact_name "${distro}")
        dir=$(artifactory_pkg_dir "${ARTIFACTS_DOMAIN}" "${artifact_distro}" "x86_64" "${pkg_type}" "aerospike-server-enterprise")
        [ -z "${dir}" ] && continue
        rc=0
        names=$(artifactory_list_names "${dir}") || rc=$?
        if [ "${rc}" -eq "${AS_LIST_ERROR}" ]; then
            log_warn "Cannot read ${dir} - treating ${lineage} as unresolved rather than absent"
            failed=true
            continue
        fi
        versions="${versions}
$(printf '%s\n' "${names}" | grep -E "\\.${pkg_type}\$" |
            grep -oE "${lineage_re}\\.[0-9]+\\.[0-9]+" || true)"
    done

    # || true: grep exits 1 when no version matched, which under set -e would
    # kill the caller's $(...) assignment instead of yielding an empty result.
    echo "${versions}" | grep -vE '^$' | sort -V | tail -1 || true

    # A version found despite one bad listing is still a real answer; only
    # report an error when nothing resolved and a listing failed, because that
    # is the case indistinguishable from "not published".
    if [ "${failed}" = true ] && [ -z "$(echo "${versions}" | grep -vE '^$' || true)" ]; then
        return "${AS_LIST_ERROR}"
    fi
    return "${AS_LIST_OK}"
}

# Find local server package file; echo path if found, else empty. Search base and base/version.
# Tries exact filename first, then glob match (e.g. *server*edition*arch*.rpm).
# base_dir may also be a single .deb/.rpm file, which is used directly when its
# filename names the requested package type, edition, version, distro and arch.
function find_local_server_package() {
    local base_dir=$1
    local artifact_distro=$2
    local edition=$3
    local version=$4
    local arch=$5
    local pkg_type=$6

    if [ -f "${base_dir}" ]; then
        # Enforce the same facts the directory branches below enforce, so a
        # single file cannot be handed to the wrong package type, version,
        # edition, distro or arch. -d ubuntu expands to one target per concrete
        # distro, each with a resolved artifact_distro, so testing it here skips
        # the mismatched targets rather than all but one.
        local _name _ok=true
        _name=$(basename "${base_dir}")
        [[ "${_name}" == *".${pkg_type}" ]] || _ok=false
        [[ "${_name}" == *"${edition}"* ]] || _ok=false
        pkg_name_matches_version "${_name}" "${version}" || _ok=false
        [[ "${_name}" == *"${artifact_distro}"* ]] || _ok=false
        pkg_name_matches_arch "${_name}" "${arch}" || _ok=false
        if "${_ok}"; then
            echo "${base_dir}"
        else
            echo ""
        fi
        return
    fi

    if [ -d "${base_dir}" ]; then
        base_dir=$(
            cd "${base_dir}" || exit 1
            pwd
        )
    fi

    if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
        echo ""
        return
    fi

    local deb_arch="${arch}"
    [ "${arch}" = "x86_64" ] && deb_arch="amd64"
    [ "${arch}" = "aarch64" ] && deb_arch="arm64"

    local lineage
    lineage=$(echo "${version}" | cut -d. -f1-2)

    # Naming: aerospike-server-<edition>[-_]<version>-<rev>[._]<distro>[._]<arch>.<ext>
    #   RPM: aerospike-server-<edition>-<version>-<rev>.<distro>.<arch>.rpm
    #   DEB: aerospike-server-<edition>_<version>-<rev><distro>_<arch>.deb
    # <version> can be 7.1.0.22 or 7.1.0.22-start-16-g216a75438
    # <rev> is the package revision (e.g. 1, 12)

    local search_dirs=("${base_dir}" "${base_dir}/${version}" "${base_dir}/${lineage}" "${base_dir}/${lineage}/${version}")
    local dir f found

    if [ "${pkg_type}" = "rpm" ]; then
        # Exact: edition-version-rev.distro.arch.rpm (try common revisions)
        for dir in "${search_dirs[@]}"; do
            [ -d "${dir}" ] || continue
            for f in "${dir}"/aerospike-server-"${edition}"-"${version}"-*."${artifact_distro}"."${arch}".rpm; do
                [ -f "${f}" ] && echo "${f}" && return
            done
        done
        # Glob: server rpm matching edition + VERSION + distro + arch (version-aware
        # to avoid picking up stale packages from a previous -u run).
        for dir in "${search_dirs[@]}"; do
            [ -d "${dir}" ] || continue
            found=$(_pick_versioned "${version}" \
                "$(find "${dir}" -maxdepth 1 -type f -name "aerospike-server*${edition}*${version}*${artifact_distro}*${arch}*.rpm" 2>/dev/null)")
            [ -n "${found}" ] && echo "${found}" && return
        done
    else
        # Exact: edition_version-rev<distro>_arch.deb (glob the -rev part)
        for dir in "${search_dirs[@]}"; do
            [ -d "${dir}" ] || continue
            for f in "${dir}"/aerospike-server-"${edition}"_"${version}"-*"${artifact_distro}"_"${deb_arch}".deb; do
                [ -f "${f}" ] && echo "${f}" && return
            done
        done
        # Glob: server deb matching edition + VERSION + distro + arch (version-aware
        # to avoid picking up stale packages from a previous -u run).
        for dir in "${search_dirs[@]}"; do
            [ -d "${dir}" ] || continue
            found=$(_pick_versioned "${version}" \
                "$(find "${dir}" -maxdepth 1 -type f -name "aerospike-server*${edition}*${version}*${artifact_distro}*${deb_arch}*.deb" 2>/dev/null)")
            [ -n "${found}" ] && echo "${found}" && return
        done
    fi

    # Last resort: any file with edition, VERSION, distro, AND arch in name.
    # Version is required here too so stale packages from prior runs are never used.
    for dir in "${search_dirs[@]}"; do
        [ -d "${dir}" ] || continue
        if [ "${pkg_type}" = "rpm" ]; then
            for f in "${dir}"/*.rpm; do
                [ -f "${f}" ] || continue
                [[ "${f}" = *"${edition}"* ]] && pkg_name_matches_version "${f}" "${version}" && [[ "${f}" = *"${artifact_distro}"* ]] && [[ "${f}" = *"${arch}"* ]] && echo "${f}" && return
            done
        else
            for f in "${dir}"/*.deb; do
                [ -f "${f}" ] || continue
                [[ "${f}" = *"${edition}"* ]] && pkg_name_matches_version "${f}" "${version}" && [[ "${f}" = *"${artifact_distro}"* ]] && [[ "${f}" = *"${deb_arch}"* ]] && echo "${f}" && return
            done
        fi
    done

    # Recursive: search nested layouts (e.g. releases/7.1/.../pkg), version-aware.
    if [ -d "${base_dir}" ]; then
        if [ "${pkg_type}" = "rpm" ]; then
            found=$(_pick_versioned "${version}" \
                "$(find "${base_dir}" -type f -name "aerospike-server*${edition}*${version}*${artifact_distro}*${arch}*.rpm" 2>/dev/null)")
        else
            found=$(_pick_versioned "${version}" \
                "$(find "${base_dir}" -type f -name "aerospike-server*${edition}*${version}*${artifact_distro}*${deb_arch}*.deb" 2>/dev/null)")
        fi
        [ -n "${found}" ] && echo "${found}" && return
    fi
    echo ""
}

# Discover latest version for a lineage from a local artifacts directory (no HTTP).
# Supports: version subdirs (8.1.1.0), edition/version (aerospike-server-enterprise/8.1.1.0), or package filenames.
function find_latest_version_for_lineage_local() {
    local lineage=$1
    local base_dir="${ARTIFACTS_DOMAIN}"
    # Resolve relative path (e.g. ../signed-artifacts) against current dir (script dir when run from docker-build.sh)
    [[ "${base_dir}" != /* ]] && [[ "${base_dir}" != http* ]] && base_dir="$(pwd)/${base_dir}"

    # -u given a single package file: take the version from its filename.
    if [ -f "${base_dir}" ]; then
        basename "${base_dir}" |
            grep -oE "${lineage//./\\.}\\.[0-9]+\\.[0-9]+(-start-[0-9]+(-g[a-f0-9]+)?|-rc[0-9]+)?" |
            head -1 || true
        return
    fi

    [ -d "${base_dir}" ] || return
    base_dir=$(
        cd "${base_dir}" || exit 1
        pwd
    )

    local versions=""
    # Direct version subdirs (e.g. 8.1.1.0, 7.1.0.21)
    local d
    for d in "${base_dir}"/*/; do
        [ -d "${d}" ] || continue
        d=$(basename "${d}")
        if [[ "${d}" =~ ^${lineage}\.[0-9]+\.[0-9]+ ]]; then
            versions="${versions} ${d}"
        fi
    done
    # Edition subdirs then version subdirs (e.g. aerospike-server-enterprise/8.1.1.0/)
    local ed
    for ed in aerospike-server-community aerospike-server-enterprise aerospike-server-federal; do
        [ -d "${base_dir}/${ed}" ] || continue
        for d in "${base_dir}/${ed}"/*/; do
            [ -d "${d}" ] || continue
            d=$(basename "${d}")
            if [[ "${d}" =~ ^${lineage}\.[0-9]+\.[0-9]+ ]]; then
                versions="${versions} ${d}"
            fi
        done
    done
    # Package filenames (e.g. aerospike-server-enterprise_8.1.1.0-12ubuntu22.04_amd64.deb
    #   or aerospike-server-enterprise-8.1.1.0-start-16-g216a75438-1.el9.x86_64.rpm)
    # Extract version only (not the -<rev><distro> suffix).
    local ver_re="${lineage}\.[0-9]+\.[0-9]+(-start-[0-9]+(-g[a-f0-9]+)?|-rc[0-9]+)?"
    if [ -z "${versions}" ] && compgen -G "${base_dir}/*.deb" >/dev/null 2>&1; then
        versions=$(for f in "${base_dir}"/*.deb; do
            [ -f "${f}" ] && basename "${f}" | grep -oE "${ver_re}" || true
        done)
    fi
    if [ -z "${versions}" ] && compgen -G "${base_dir}/*.rpm" >/dev/null 2>&1; then
        versions=$(for f in "${base_dir}"/*.rpm; do
            [ -f "${f}" ] && basename "${f}" | grep -oE "${ver_re}" || true
        done)
    fi
    # Recursive find for nested layout (e.g. lineage/version/pkgs)
    if [ -z "${versions}" ] && [ -d "${base_dir}/${lineage}" ]; then
        for d in "${base_dir}/${lineage}"/*/; do
            [ -d "${d}" ] || continue
            d=$(basename "${d}")
            if [[ "${d}" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                versions="${versions} ${d}"
            fi
        done
    fi

    echo "${versions}" | tr ' ' '\n' | sort -V 2>/dev/null | tail -1
}

# Find the latest version for a release lineage (e.g., 7.1 -> 7.1.0.20)
function find_latest_version_for_lineage() {
    local lineage=$1
    local url

    if is_local_artifacts_dir; then
        find_latest_version_for_lineage_local "${lineage}"
        return
    fi

    if is_artifactory_repo; then
        find_latest_version_for_lineage_artifactory "${lineage}"
        return
    fi

    if is_direct_url; then
        url="${ARTIFACTS_DOMAIN}/"
    else
        url="${ARTIFACTS_DOMAIN}/aerospike-server-enterprise/"
    fi

    fetch "version" "${url}" 2>/dev/null |
        grep -oE "\"${lineage}\.[0-9]+\.[0-9]+(-[a-z0-9]+(-[0-9]+(-g[a-f0-9]+)?)?)?/?\"" |
        tr -d '"/' | sort -V | tail -1 || true
}

# Find the tools version for a server version (same for all editions/distros)
function find_tools_version() {
    local version=$1
    local url

    if is_local_artifacts_dir; then
        # Local dir: scan for any TGZ bundle whose name embeds _tools-<ver>_
        # grep exits 1 when there are no matches; || true prevents pipefail from
        # propagating that into a set -e exit in the caller.
        local base_dir="${ARTIFACTS_DOMAIN}"
        [[ "${base_dir}" != /* ]] && base_dir="$(pwd)/${base_dir}"
        find "${base_dir}" -type f -name "*${version}*_tools-*.tgz" 2>/dev/null |
            grep -oE "_tools-[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+(-[0-9]+)?)?_" |
            head -1 | sed 's/_tools-//; s/_$//' || true
        return
    fi

    # JFrog repos hold native .deb/.rpm only - no TGZ bundles to derive tools from.
    if is_artifactory_repo; then
        echo ""
        return
    fi

    if is_direct_url; then
        url="${ARTIFACTS_DOMAIN}/${version}/"
    else
        url="${ARTIFACTS_DOMAIN}/aerospike-server-enterprise/${version}/"
    fi

    local page
    page=$(fetch "tools" "${url}" 2>/dev/null)

    # Extract tools version from any available package (|| true: grep exits 1 on no match)
    echo "${page}" | grep -oE "_tools-[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9]+(-[0-9]+)?)?_" |
        head -1 | sed 's/_tools-//; s/_$//' || true
}

# Find local TGZ bundle for given parameters; echo absolute path or empty.
function find_local_tgz_package() {
    local base_dir=$1 artifact_distro=$2 edition=$3 version=$4 tools_version=$5 arch=$6

    if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
        echo ""
        return
    fi

    [[ "${base_dir}" != /* ]] && base_dir="$(pwd)/${base_dir}"
    [ -d "${base_dir}" ] || {
        echo ""
        return
    }
    base_dir=$(cd "${base_dir}" && pwd)

    local tgz_name="aerospike-server-${edition}_${version}_tools-${tools_version}_${artifact_distro}_${arch}.tgz"
    local search_dirs=(
        "${base_dir}"
        "${base_dir}/${version}"
        "${base_dir}/aerospike-server-${edition}"
        "${base_dir}/aerospike-server-${edition}/${version}"
    )
    local dir f
    for dir in "${search_dirs[@]}"; do
        [ -d "${dir}" ] || continue
        f="${dir}/${tgz_name}"
        [ -f "${f}" ] && echo "${f}" && return
    done
    # Recursive fallback (nested release layouts)
    f=$(find "${base_dir}" -type f -name "${tgz_name}" 2>/dev/null | head -1)
    [ -n "${f}" ] && echo "${f}" && return
    echo ""
}

# Get the download link for a package (tgz bundle)
function get_package_link() {
    local artifact_distro=$1
    local edition=$2
    local version=$3
    local tools_version=$4
    local arch=$5

    # Federal doesn't support arm64
    if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
        echo ""
        return
    fi

    # Local dir: resolve the actual file path rather than building a computed URL
    if is_local_artifacts_dir; then
        find_local_tgz_package "${ARTIFACTS_DOMAIN}" "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "${arch}"
        return
    fi

    local base_url
    if is_direct_url; then
        base_url="${ARTIFACTS_DOMAIN}"
    else
        base_url="${ARTIFACTS_DOMAIN}/aerospike-server-${edition}"
    fi

    echo "${base_url}/${version}/aerospike-server-${edition}_${version}_tools-${tools_version}_${artifact_distro}_${arch}.tgz"
}

# Get server package link for native format (rpm or deb) - when tgz is not available.
# Supports version-based layouts (default) and both JFrog Artifactory layouts.
function get_server_package_link_native() {
    local artifact_distro=$1
    local edition=$2
    local version=$3
    # shellcheck disable=SC2034
    local _unused=$4 # tools_version (kept for call-site compat)
    local arch=$5
    local pkg_type=$6

    if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
        echo ""
        return
    fi

    # Local dir: use find_local_server_package to locate the actual file (handles
    # flat, versioned, edition-prefixed, and nested directory layouts).
    if is_local_artifacts_dir; then
        find_local_server_package "${ARTIFACTS_DOMAIN}" "${artifact_distro}" "${edition}" "${version}" "${arch}" "${pkg_type}"
        return
    fi

    local deb_arch="${arch}"
    [ "${arch}" = "x86_64" ] && deb_arch="amd64"
    [ "${arch}" = "aarch64" ] && deb_arch="arm64"

    # JFrog repos embed a package revision that is not derivable from the server
    # version (e.g. 8.1.2.4-4), so the exact filename is discovered by listing
    # the package directory rather than composed from the version alone.
    if is_artifactory_repo; then
        local dir link version_re distro_re
        version_re=$(_ere_quote "${version}")
        distro_re=$(_ere_quote "${artifact_distro}")
        dir=$(artifactory_pkg_dir "${ARTIFACTS_DOMAIN}" "${artifact_distro}" "${arch}" "${pkg_type}" "aerospike-server-${edition}")
        # Exact <version>-<rev> match first, then a looser one so pre-release
        # version strings (e.g. 8.1.1.0-start-16-gea126d3) still resolve. Both
        # patterns are tried against one listing rather than one call each.
        local rc=0
        if [ "${pkg_type}" = "rpm" ]; then
            link=$(artifactory_pick_latest_for_arch "${dir}" "${arch}" \
                "^aerospike-server-${edition}-${version_re}-[0-9]+\\.${distro_re}\\.${arch}\\.rpm$" \
                "^aerospike-server-${edition}-${version_re}[-.].*\\.${arch}\\.rpm$") || rc=$?
        else
            link=$(artifactory_pick_latest_for_arch "${dir}" "${arch}" \
                "^aerospike-server-${edition}_${version_re}-[0-9]+${distro_re}_${deb_arch}\\.deb$" \
                "^aerospike-server-${edition}_${version_re}[-_].*_${deb_arch}\\.deb$") || rc=$?
        fi
        echo "${link}"
        [ "${rc}" -eq "${AS_LIST_ERROR}" ] && return "${AS_LIST_ERROR}"
        return
    fi

    local base_url
    if is_direct_url; then
        base_url="${ARTIFACTS_DOMAIN}"
    else
        base_url="${ARTIFACTS_DOMAIN}/aerospike-server-${edition}"
    fi

    if [ "${pkg_type}" = "rpm" ]; then
        echo "${base_url}/${version}/aerospike-server-${edition}-${version}-1.${artifact_distro}.${arch}.rpm"
    else
        # Include artifact_distro in filename so ubuntu24.04 image gets ubuntu24.04-built package (not ubuntu22.04).
        # Matches find_local_server_package pattern: edition_version${artifact_distro}_arch.deb
        echo "${base_url}/${version}/aerospike-server-${edition}_${version}${artifact_distro}_${deb_arch}.deb"
    fi
}

# Find a local aerospike-asadm package; echo path if found, else empty.
function find_local_asadm_package() {
    local base_dir=$1 artifact_distro=$2 arch=$3 pkg_type=$4

    [[ "${base_dir}" != /* ]] && base_dir="$(pwd)/${base_dir}"
    [ -d "${base_dir}" ] || {
        echo ""
        return
    }
    base_dir=$(cd "${base_dir}" && pwd)

    local ext="deb"
    [ "${pkg_type}" = "rpm" ] && ext="rpm"

    local candidates found qualified unqualified f
    candidates=$(find "${base_dir}" -type f -name "aerospike-asadm[-_]*.${ext}" 2>/dev/null |
        while read -r f; do
            pkg_name_matches_arch "${f}" "${arch}" && echo "${f}"
        done)

    # Both tiers test the basename, never the path: candidates are absolute
    # paths from a recursive find, so a path test makes ~/pkgs/ubuntu24.04/
    # qualify a ubuntu22.04 package, and excluding known distros by path drops
    # legitimate distro-less packages that merely live under rel9/ or model3/.
    qualified=""
    unqualified=""
    while IFS= read -r f; do
        [ -n "${f}" ] || continue
        if [[ "$(basename "${f}")" == *"${artifact_distro}"* ]]; then
            qualified+="${f}"$'\n'
        elif ! pkg_name_names_a_distro "${f}"; then
            unqualified+="${f}"$'\n'
        fi
    done <<<"${candidates}"

    # Distro-qualified match first, so an el10 (or ubuntu24.04) package is never
    # handed to an el9 (or ubuntu22.04) image. The fallback accepts only
    # packages that name no distro at all -- hand-built or hand-renamed ones --
    # rather than any package, which is what let a wrong-distro package through.
    found=$(printf '%s' "${qualified}" | grep -vE '^$' | sort -V | tail -1 || true)
    if [ -z "${found}" ]; then
        found=$(printf '%s' "${unqualified}" | grep -vE '^$' | sort -V | tail -1 || true)
    fi
    echo "${found}"
}

# Get the link for the latest standalone aerospike-asadm package.
#
# Source precedence:
#   1. --no-asadm            -> empty (asadm left out entirely)
#   2. -A/--asadm-url        -> that source
#   3. a local -u artifacts dir that already carries an asadm package, so local
#      pre-release builds stay self-contained without needing -A
#   4. the JFrog repo for this package format
#
# The source may be a direct package URL/path, a local directory, a JFrog repo,
# or a plain HTTP directory index. Echoes empty when no package is published for
# the requested distro/arch, which leaves asadm out rather than failing the build.
#
# Only the native install path calls this: the TGZ bundles carry asadm inside
# aerospike-tools, so installing it again there would collide.
function get_asadm_package_link_native() {
    local artifact_distro=$1 arch=$2 pkg_type=$3

    if [ "${ASADM_DISABLED}" = true ]; then
        echo ""
        return
    fi

    # A local -u is the whole answer: "build from local packages" must not make
    # outbound requests to a host the user never named. Matches how
    # get_server_package_link_native and get_package_link treat a local source.
    if [ -z "${ASADM_DOMAIN}" ] && is_local_artifacts_dir; then
        find_local_asadm_package "${ARTIFACTS_DOMAIN}" "${artifact_distro}" "${arch}" "${pkg_type}"
        return
    fi

    local base
    base=$(asadm_domain_for_pkg_type "${pkg_type}")
    [ -z "${base}" ] && {
        echo ""
        return
    }

    # Direct package URL or file path - used verbatim, no discovery. Applies
    # only to the arch its filename names, so a single -A package cannot be
    # installed into the other arch's image.
    case "${base}" in
    *.deb | *.rpm)
        # A local path that does not exist is a typo, not an absent package:
        # say so rather than silently dropping asadm from the image.
        if [[ "${base}" != http* ]] && [ ! -f "${base}" ]; then
            log_warn "asadm package not found: ${base}"
            echo ""
        elif pkg_name_matches_arch "${base}" "${arch}"; then
            echo "${base}"
        else
            echo ""
        fi
        return
        ;;
    esac

    if [[ "${base}" != http* ]]; then
        find_local_asadm_package "${base}" "${artifact_distro}" "${arch}" "${pkg_type}"
        return
    fi

    local dir distro_re
    distro_re=$(_ere_quote "${artifact_distro}")
    if is_artifactory_url "${base}"; then
        dir=$(artifactory_pkg_dir "${base}" "${artifact_distro}" "${arch}" "${pkg_type}" "aerospike-asadm")
    else
        # Plain HTTP directory index holding the packages directly.
        dir="${base}"
    fi

    # Distro-qualified match first, then any asadm package for this arch, so
    # plain directories that do not embed the distro in the filename still work.
    # Both patterns share one listing.
    local link ext="deb" rc=0
    [ "${pkg_type}" = "rpm" ] && ext="rpm"
    link=$(artifactory_pick_latest_for_arch "${dir}" "${arch}" \
        "^aerospike-asadm[-_].*${distro_re}.*\\.${ext}$" \
        "^aerospike-asadm[-_].*\\.${ext}$") || rc=$?
    echo "${link}"

    # A source the user named explicitly either yields a package or says why
    # not. Silence is only acceptable for the default repo, where "not published
    # yet" is the expected answer and building without asadm is sanctioned.
    if [ "${rc}" -eq "${AS_LIST_ERROR}" ]; then
        if [ -n "${ASADM_DOMAIN}" ]; then
            log_warn "Cannot read the asadm source you gave with -A: ${dir}"
            return "${AS_LIST_ERROR}"
        fi
        log_warn "Cannot read the default asadm repo (${dir}) - continuing without asadm"
    fi
}

# Find local tools package; echo path if found, else empty.
function find_local_tools_package() {
    local base_dir=$1 artifact_distro=$2 edition=$3 version=$4 tools_version=$5 arch=$6 pkg_type=$7

    if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
        echo ""
        return
    fi

    [[ "${base_dir}" != /* ]] && base_dir="$(pwd)/${base_dir}"
    [ -d "${base_dir}" ] || {
        echo ""
        return
    }
    base_dir=$(cd "${base_dir}" && pwd)

    local deb_arch="${arch}"
    [ "${arch}" = "x86_64" ] && deb_arch="amd64"
    [ "${arch}" = "aarch64" ] && deb_arch="arm64"

    local search_dirs=("${base_dir}" "${base_dir}/${version}" "${base_dir}/aerospike-server-${edition}" "${base_dir}/aerospike-server-${edition}/${version}")
    local dir f

    if [ "${pkg_type}" = "rpm" ]; then
        for dir in "${search_dirs[@]}"; do
            [ -d "${dir}" ] || continue
            for f in "${dir}"/aerospike-tools-"${tools_version}"-*."${artifact_distro}"."${arch}".rpm; do
                [ -f "${f}" ] && echo "${f}" && return
            done
        done
        f=$(find "${base_dir}" -type f -name "aerospike-tools*${tools_version}*${artifact_distro}*${arch}*.rpm" 2>/dev/null | head -1)
    else
        for dir in "${search_dirs[@]}"; do
            [ -d "${dir}" ] || continue
            for f in "${dir}"/aerospike-tools_"${tools_version}"_"${deb_arch}".deb \
                "${dir}"/aerospike-tools_"${tools_version}"*_"${deb_arch}".deb; do
                [ -f "${f}" ] && echo "${f}" && return
            done
        done
        f=$(find "${base_dir}" -type f -name "aerospike-tools*${tools_version}*${deb_arch}*.deb" 2>/dev/null | head -1)
    fi
    [ -n "${f}" ] && echo "${f}" && return
    echo ""
}

# Get tools package link for native format (rpm or deb)
function get_tools_package_link_native() {
    local artifact_distro=$1
    local edition=$2
    local version=$3
    local tools_version=$4
    local arch=$5
    local pkg_type=$6

    if [ "${arch}" = "aarch64" ] && [ "${edition}" = "federal" ]; then
        echo ""
        return
    fi

    # Local dir: search for the actual tools package file
    if is_local_artifacts_dir; then
        find_local_tools_package "${ARTIFACTS_DOMAIN}" "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "${arch}" "${pkg_type}"
        return
    fi

    local base_url path_prefix
    if is_direct_url || is_artifactory_repo; then
        base_url="${ARTIFACTS_DOMAIN}"
    else
        base_url="${ARTIFACTS_DOMAIN}/aerospike-server-${edition}"
    fi

    if is_artifactory_repo; then
        path_prefix="${artifact_distro}/${arch}"
    else
        path_prefix="${version}"
    fi

    if [ "${pkg_type}" = "rpm" ]; then
        echo "${base_url}/${path_prefix}/aerospike-tools-${tools_version}-1.${artifact_distro}.${arch}.rpm"
    else
        local deb_arch="${arch}"
        [ "${arch}" = "x86_64" ] && deb_arch="amd64"
        echo "${base_url}/${path_prefix}/aerospike-tools_${tools_version}_${deb_arch}.deb"
    fi
}

# Fetch SHA256 for any package URL or local file path (reads link.sha256 sidecar).
#
# Every branch assigns into one variable and the result is validated once, at
# the end. A checksum is substituted into a single-quoted shell assignment in
# the generated Dockerfile (serverSha='...', asadmSha='...'), so a value
# carrying a quote closes it and the remainder runs as root at docker build
# time -- from a Dockerfile committed to a public repo, and before the
# sha256sum check it was supposed to feed. Remote sidecars and the
# X-Checksum-Sha256 header are attacker-controlled over plain HTTP; a local
# sidecar is whatever scripts/shasum-artifacts.sh or the user put next to the
# package. Neither is trusted, so both go through the same gate.
function fetch_sha_for_link() {
    local link=$1
    local sha=""
    [ -z "${link}" ] && {
        echo ""
        return
    }
    if [[ "${link}" != http* ]]; then
        # Local file: read .sha256 sidecar if present, else compute the hash.
        # The || true is load-bearing: without it pipefail turns a cut failure
        # into a caller exit from inside $( ).
        if [ -f "${link}.sha256" ]; then
            sha=$(cut -f1 -d' ' <"${link}.sha256" || true)
        elif [ -f "${link}" ]; then
            sha=$(sha256sum "${link}" 2>/dev/null | cut -f1 -d' ' || true)
        fi
    else
        sha=$(fetch "sha" "${link}.sha256" 2>/dev/null | cut -f1 -d' ' || true)
        if [ -z "${sha}" ]; then
            # Fall back to the digest header when no .sha256 sidecar is served.
            sha=$(curl -fsSLI "${link}" 2>/dev/null | tr -d '\r' |
                awk 'tolower($1) == "x-checksum-sha256:" { print $2 }' | tail -1 || true)
        fi
    fi
    if [ -n "${sha}" ] && [[ ! "${sha}" =~ ^[0-9a-fA-F]{64}$ ]]; then
        log_warn "Ignoring malformed SHA256 for ${link}"
        sha=""
    fi
    echo "${sha}"
}

# Drop any arch whose remote package has no usable checksum, reading and writing
# the caller's x86_link/arm_link/asadm_*_link (the same dynamic scoping
# resolve_packages uses). A live URL beside an empty digest is not a degraded
# build, it is an unbuildable one: the install script runs
# `sha256sum --strict --check` on the empty value and the RUN fails. Both the
# generate and update paths call this, so the two cannot drift apart.
#
# The arch is dropped rather than the whole target: get_package_link composes a
# tgz URL with no existence check, so when only one arch is published a
# whole-target skip would lose the arch that does build.
function drop_unchecksummed_arches() {
    if [[ "${x86_link:-}" == http* ]] && [ -z "${x86_sha:-}" ]; then
        log_warn "    No SHA256 for ${x86_link} - dropping amd64"
        x86_link=""
    fi
    if [[ "${arm_link:-}" == http* ]] && [ -z "${arm_sha:-}" ]; then
        log_warn "    No SHA256 for ${arm_link} - dropping arm64"
        arm_link=""
    fi
    # asadm is explicitly optional, so an absent one is not a build failure.
    if [[ "${asadm_x86_link:-}" == http* ]] && [ -z "${asadm_x86_sha:-}" ]; then
        log_warn "    No SHA256 for ${asadm_x86_link} - amd64 asadm dropped"
        asadm_x86_link=""
    fi
    if [[ "${asadm_arm_link:-}" == http* ]] && [ -z "${asadm_arm_sha:-}" ]; then
        log_warn "    No SHA256 for ${asadm_arm_link} - arm64 asadm dropped"
        asadm_arm_link=""
    fi
}

# Fetch SHA256 checksum for a package (tgz)
function fetch_package_sha() {
    local link
    link="$(get_package_link "$@")"
    [ -z "${link}" ] && {
        echo ""
        return
    }
    fetch_sha_for_link "${link}"
}
