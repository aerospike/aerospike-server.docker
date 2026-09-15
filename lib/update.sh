#!/usr/bin/env bash
# In-place Dockerfile update: refresh install block and patch version label.
# Used by default (no -g flag).
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/log.sh, lib/support.sh, lib/fetch.sh, lib/sh_to_dockerfile_run.sh

set -Eeuo pipefail

# Portable in-place sed (BSD sed on macOS vs GNU sed on Linux)
_sed_i() {
    if [[ "$OSTYPE" == darwin* ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# Refresh the embedded install script block in a Dockerfile (same layout as emit.sh).
# inst = path to the source install script.
# The script is NOT copied into the build context — DOI rejects COPY of
# build-time-only scripts. Logic is inlined as a RUN \ block via the converter.
# Package URL/SHA placeholders are substituted using caller-scoped variables:
#   x86_link  x86_sha  arm_link  arm_sha
#   asadm_x86_link  asadm_x86_sha  asadm_arm_link  asadm_arm_sha
# (all set by resolve_packages)
function _dockerfile_refresh_install_block() {
    local df=$1
    local inst=$2

    # Temp files; cleaned up on function return (including on error).
    local nbf tmp
    nbf=$(mktemp)
    tmp=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '${nbf}' '${tmp}'" RETURN

    # Step A: build the new install block into a temp file.
    _sh_to_dockerfile_run "${inst}" >"${nbf}"

    # Step B: substitute package URL/SHA placeholders.
    # Uses caller-scoped x86_link, x86_sha, arm_link, arm_sha (from resolve_packages).
    local pkg_type
    pkg_type=$(support_distro_to_pkg_type "$(basename "$(dirname "${df}")")")

    local -a SUBST_ARGS=()
    _build_subst_args "${pkg_type}"
    _sed_i "${SUBST_ARGS[@]}" "${nbf}"

    # Ensure exactly one trailing blank line (separator before the next instruction).
    printf '\n' >>"${nbf}"

    # Step C: replace the install block in whichever form it currently appears.
    #   Form 1 (current):  anchor + "# hadolint..." + "RUN \" + continuation lines
    #   Form 2 (previous): anchor + "COPY install.sh" + "# hadolint..." + "RUN bash"
    #   Form 3 (oldest):   anchor + BuildKit heredoc content until AEROSPIKE_INSTALL
    awk -v nbf="${nbf}" -v src="${df}" '
    function emit_new_block(    line) {
        while ((getline line < nbf) > 0) print line
        close(nbf)
    }
    BEGIN { state = "looking"; form = "" }
    state == "done" { print; next }
    state == "looking" && /^# Install Aerospike Server and Tools$/ {
        state = "consuming"; form = ""; next
    }
    state == "consuming" {
        if (form == "") {
            if (/^# hadolint/)        { form = "run1";    next }
            if (/^COPY install\.sh /) { form = "run2";    next }
            if (/<</)                 { form = "heredoc"; next }
            # Unrecognised line after anchor — emit block and keep line
            emit_new_block(); state = "done"; print; next
        }
        if (form == "run1") {
            if (/^RUN \\/) { next }        # RUN \ header
            if (/^[ \t]/)  { next }        # continuation lines
            if (/^$/)      { next }        # trailing blank lines after block
            emit_new_block(); state = "done"; print; next
        }
        if (form == "run2") {
            if (/^# hadolint/) { next }
            if (/^RUN bash /)  { emit_new_block(); state = "done"; next }
            emit_new_block(); state = "done"; print; next
        }
        if (form == "heredoc") {
            if (/^AEROSPIKE_INSTALL$/) { emit_new_block(); state = "done"; next }
            next
        }
    }
    { print }
    END {
        if (state != "done") {
            print src ": could not replace install block" > "/dev/stderr"
            exit 1
        }
    }
    ' "${df}" >"${tmp}" && mv "${tmp}" "${df}"

    # Step D: cleanup passes.
    # Remove BuildKit-only parser directive (DOI legacy builder does not use it).
    _sed_i '/^# syntax=docker\/dockerfile:/d' "${df}"
    # Remove old ARG lines for package URLs/SHAs (replaced by hardcoded values in RUN block).
    _sed_i '/^ARG AEROSPIKE_X86_64_LINK=/d' "${df}"
    _sed_i '/^ARG AEROSPIKE_SHA_X86_64=/d' "${df}"
    _sed_i '/^ARG AEROSPIKE_AARCH64_LINK=/d' "${df}"
    _sed_i '/^ARG AEROSPIKE_SHA_AARCH64=/d' "${df}"
    _sed_i '/^ARG AEROSPIKE_COMPAT_LIBS=/d' "${df}"
    _sed_i '/^ARG AEROSPIKE_LOCAL_PKG=/d' "${df}"
    # Remove old local-pkg COPY lines (no longer in build context).
    _sed_i '/^COPY server_/d' "${df}"
    # Collapse multiple consecutive blank lines to one (left by removed ARG blocks).
    awk 'prev=="" && /^$/ && blank { next } /^$/ { blank=1 } !/^$/ { blank=0 } { prev=$0; print }' \
        "${df}" >"${tmp}" && mv "${tmp}" "${df}"

    # Step E: inject ENV AEROSPIKE_LINUX_BASE after ARG AEROSPIKE_EDITION if
    # missing. A blank line follows, matching the generated header: the update
    # path must emit the exact shape emit.sh generates, or CI's
    # regenerate-and-diff gate flags every file an update run last touched.
    if ! grep -qF 'ENV AEROSPIKE_LINUX_BASE=' "${df}"; then
        local base_img
        base_img=$(awk '/^FROM /{print $2; exit}' "${df}")
        if [ -n "${base_img}" ]; then
            awk -v base="${base_img}" '
            /^ARG AEROSPIKE_EDITION=/ {
                print
                print ""
                print "ENV AEROSPIKE_LINUX_BASE=\"" base "\""
                next
            }
            { print }
            ' "${df}" >"${tmp}" && mv "${tmp}" "${df}"
        fi
    fi

    # Step F: ensure STOPSIGNAL SIGTERM is present before ENTRYPOINT.
    if ! grep -qF 'STOPSIGNAL SIGTERM' "${df}"; then
        awk '!found && /^ENTRYPOINT \[/ {
            print "STOPSIGNAL SIGTERM"
            print ""
            found = 1
        } { print }' "${df}" >"${tmp}" && mv "${tmp}" "${df}"
    fi

    # Step G: ensure file starts with exactly one blank line; strip trailing whitespace.
    awk 'BEGIN{skip=1} skip && /^$/{next} {skip=0; print}' "${df}" |
        {
            printf '\n'
            cat
        } >"${tmp}" && mv "${tmp}" "${df}"
    _sed_i 's/[[:space:]]*$//' "${df}"
}

# Sync the native-package COPY instruction in a Dockerfile.
#   copy_glob  non-empty (e.g. "*.deb") → ensure exactly one "COPY <glob> /tmp/aerospike/" line
#              exists immediately before the "# Install Aerospike Server" anchor.
#   copy_glob  empty → remove any such COPY line (remote-URL mode).
# Idempotent: safe to call on both new and already-updated Dockerfiles.
function _dockerfile_sync_native_copy() {
    local df=$1 copy_glob=$2
    local tmp
    tmp=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" RETURN

    if [ -n "${copy_glob}" ]; then
        local copy_line="COPY ${copy_glob} /tmp/aerospike/"
        # If the exact line already exists, nothing to do.
        if grep -qF "${copy_line}" "${df}"; then
            return 0
        fi
        # Remove any stale COPY *.deb / COPY *.rpm line first (different glob or
        # edition). Two expressions, not BRE alternation: BSD sed has no \|.
        _sed_i -e '/^COPY \*\.deb \/tmp\/aerospike\//d' \
            -e '/^COPY \*\.rpm \/tmp\/aerospike\//d' "${df}"
        # Insert the COPY line (+ blank line) immediately before the install anchor.
        awk -v cline="${copy_line}" '
        /^# Install Aerospike/ && !inserted {
            print cline
            print ""
            inserted = 1
        }
        { print }
        ' "${df}" >"${tmp}" && mv "${tmp}" "${df}"
    else
        # Remote-URL mode: remove any native-copy line. Two expressions, not
        # BRE alternation: BSD sed has no \|.
        _sed_i -e '/^COPY \*\.deb \/tmp\/aerospike\//d' \
            -e '/^COPY \*\.rpm \/tmp\/aerospike\//d' "${df}"
        # Collapse any resulting double blank line.
        awk 'prev=="" && /^$/ && blank { next } /^$/ { blank=1 } !/^$/ { blank=0 } { prev=$0; print }' \
            "${df}" >"${tmp}" && mv "${tmp}" "${df}"
    fi
}

# Remove the vendored-tini COPY block from a Dockerfile (if present from older
# Dockerfiles). Tini is now fetched at build time via curl in the install block.
function _dockerfile_remove_vendored_tini() {
    local df=$1
    if ! grep -qF 'COPY static/tini/as-tini-static-amd64' "${df}"; then
        return 0
    fi

    local tmp
    tmp=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" RETURN

    # Buffer contiguous comment lines. If the next non-comment line is the
    # tini COPY line, discard the buffer and the COPY line. Otherwise flush.
    awk '
    /^COPY static\/tini\/as-tini-static-amd64/ {
        delete buf; buf_n = 0; next
    }
    /^#/ { buf[++buf_n] = $0; next }
    {
        for (i = 1; i <= buf_n; i++) print buf[i]
        delete buf; buf_n = 0
        print
    }
    END {
        for (i = 1; i <= buf_n; i++) print buf[i]
    }
    ' "${df}" >"${tmp}" && mv "${tmp}" "${df}"
}

# resolve_packages distro edition version single_arch pkg_type
# Outputs: x86_link x86_sha arm_link arm_sha
#          asadm_x86_link asadm_x86_sha asadm_arm_link asadm_arm_sha
#          server_unreadable asadm_unreadable
# Sets the variables above in the caller's scope via dynamic scoping.
function resolve_packages() {
    local artifact_distro=$1 edition=$2 version=$3 single_arch=$4
    local pkg_type=$5

    x86_link=""
    x86_sha=""
    arm_link=""
    arm_sha=""
    asadm_x86_link=""
    asadm_x86_sha=""
    asadm_arm_link=""
    asadm_arm_sha=""
    # shellcheck disable=SC2034  # consumed by callers via dynamic scoping
    server_unreadable=false
    # shellcheck disable=SC2034  # consumed by caller (generate.sh) via dynamic scoping
    asadm_unreadable=false

    # Each requested arch is probed independently so a single-arch build
    # (-a arm64) is not abandoned when the other arch has no package - and an
    # arch the user excluded is never resolved at all: on remote sources each
    # skipped probe saves up to two listing/digest round-trips per target.
    #
    # The || guards matter beyond the flag: an unreadable listing returns
    # AS_LIST_ERROR from inside $( ), which under errexit would kill the whole
    # run with no diagnostic. The flag turns it into a per-target skip that
    # names the cause ("unreadable" is not "absent" - see artifactory_list_names).
    local _src=0
    if [ "${single_arch}" != "arm64" ]; then
        x86_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "x86_64" "${pkg_type}") || _src=$?
        x86_sha=$(fetch_sha_for_link "${x86_link}")
    fi
    if [ "${single_arch}" != "amd64" ]; then
        arm_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "aarch64" "${pkg_type}") || _src=$?
        arm_sha=$(fetch_sha_for_link "${arm_link}")
    fi
    if [ "${_src}" -eq "${AS_LIST_ERROR}" ]; then
        # shellcheck disable=SC2034  # consumed by callers via dynamic scoping
        server_unreadable=true
    fi

    if [ -n "${x86_link}" ] || [ -n "${arm_link}" ]; then
        local _arc=0
        if [ "${single_arch}" != "arm64" ]; then
            asadm_x86_link=$(get_asadm_package_link_native "${artifact_distro}" "x86_64" "${pkg_type}") || _arc=$?
            asadm_x86_sha=$(fetch_sha_for_link "${asadm_x86_link}")
        fi
        if [ "${single_arch}" != "amd64" ]; then
            asadm_arm_link=$(get_asadm_package_link_native "${artifact_distro}" "aarch64" "${pkg_type}") || _arc=$?
            asadm_arm_sha=$(fetch_sha_for_link "${asadm_arm_link}")
        fi
        if [ "${_arc}" -eq "${AS_LIST_ERROR}" ]; then
            log_warn "The asadm source given with -A could not be read"
            # shellcheck disable=SC2034  # consumed by caller (generate.sh) via dynamic scoping
            asadm_unreadable=true
        fi
    fi

    drop_unchecksummed_arches
}

# _local_pkg_copy_glob pkg_type
# The COPY glob for a target whose resolved packages include a local file, or
# empty when every package is a remote URL (curl downloads those at build
# time). Reads the caller-scoped x86_link / arm_link / asadm_*_link that
# resolve_packages sets. One definition shared by the generate and update
# paths, so the two cannot disagree about when a COPY line is emitted.
function _local_pkg_copy_glob() {
    local pkg_type=$1 _pkg
    for _pkg in "${x86_link:-}" "${arm_link:-}" \
        "${asadm_x86_link:-}" "${asadm_arm_link:-}"; do
        if [[ "${_pkg}" != http* ]] && [ -n "${_pkg}" ]; then
            echo "*.${pkg_type}"
            return
        fi
    done
    echo ""
}

# _stage_local_packages target pkg_type
#
# Purge stale packages from a build context and copy in the ones this run
# resolved locally, so `COPY *.deb` picks up exactly the current set. Reads the
# caller-scoped x86_link / arm_link / asadm_*_link that resolve_packages sets.
#
# The purge is unconditional: a remote build must not keep packages a local
# build staged last run, and nothing else in the context matches these globs.
function _stage_local_packages() {
    local target=$1 pkg_type=$2

    rm -f "${target}"/aerospike-server-*."${pkg_type}" \
        "${target}"/aerospike-tools-*."${pkg_type}" \
        "${target}"/aerospike-asadm[-_]*."${pkg_type}" 2>/dev/null || true

    # Stage the server package for each arch, plus any tools package sitting
    # beside it, so apt/rpm can satisfy a hard Depends/Requires on
    # aerospike-tools that the image would otherwise fail to install.
    local _link _arch_glob _dir _tools_f
    for _link in "${x86_link:-}" "${arm_link:-}"; do
        [[ "${_link}" != http* ]] && [ -n "${_link}" ] && [ -f "${_link}" ] || continue
        cp "${_link}" "${target}/"
        _dir=$(dirname "${_link}")
        if pkg_name_matches_arch "${_link}" "x86_64"; then
            [ "${pkg_type}" = "deb" ] && _arch_glob="_amd64.deb" || _arch_glob=".x86_64.rpm"
        else
            [ "${pkg_type}" = "deb" ] && _arch_glob="_arm64.deb" || _arch_glob=".aarch64.rpm"
        fi
        _tools_f=$(find "${_dir}" -maxdepth 1 -type f -name "aerospike-tools-*${_arch_glob}" 2>/dev/null | sort -V | tail -1)
        [ -n "${_tools_f}" ] && [ -f "${_tools_f}" ] && cp "${_tools_f}" "${target}/"
    done

    local _ad
    for _ad in "${asadm_x86_link:-}" "${asadm_arm_link:-}"; do
        if [[ "${_ad}" != http* ]] && [ -n "${_ad}" ] && [ -f "${_ad}" ]; then
            cp "${_ad}" "${target}/"
        fi
    done
}

# Escape a value for use as a sed s|||-replacement: & recalls the matched
# pattern, \ starts an escape, and | is the delimiter these expressions use.
# A URL carrying any of them (a -A link with ?token=a&b, say) would otherwise
# corrupt the emitted assignment or break the expression outright.
function _sed_rhs_quote() {
    printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

# _build_subst_args pkg_type
#
# Fill the global SUBST_ARGS array with the sed expressions that replace the
# URL/SHA placeholders in an install script. One definition of which
# placeholders exist, shared by the generate path (which pipes through sed) and
# the update path (which passes them to _sed_i) -- previously two lists of eight
# expressions that had to be edited together and did not have to agree.
#
# An empty URL is meaningful: the install scripts read it as "the package was
# staged via COPY, do not download". Only an http link is substituted, so a
# local build always emits the empty form.
function _build_subst_args() {
    local pkg_type=$1
    local x86_tag arm_tag
    if [ "${pkg_type}" = "deb" ]; then
        x86_tag="AMD64"
        arm_tag="ARM64"
    else
        x86_tag="X86_64"
        arm_tag="AARCH64"
    fi

    local _su="" _ss="" _au="" _as="" _bu="" _bs="" _cu="" _cs=""
    [[ "${x86_link:-}" == http* ]] && _su=$(_sed_rhs_quote "${x86_link}") && _ss="${x86_sha:-}"
    [[ "${arm_link:-}" == http* ]] && _bu=$(_sed_rhs_quote "${arm_link}") && _bs="${arm_sha:-}"
    [[ "${asadm_x86_link:-}" == http* ]] && _au=$(_sed_rhs_quote "${asadm_x86_link}") && _as="${asadm_x86_sha:-}"
    [[ "${asadm_arm_link:-}" == http* ]] && _cu=$(_sed_rhs_quote "${asadm_arm_link}") && _cs="${asadm_arm_sha:-}"
    SUBST_ARGS=(
        -e "s|__SERVER_URL_${x86_tag}__|${_su}|g"
        -e "s|__SERVER_SHA_${x86_tag}__|${_ss}|g"
        -e "s|__SERVER_URL_${arm_tag}__|${_bu}|g"
        -e "s|__SERVER_SHA_${arm_tag}__|${_bs}|g"
        -e "s|__ASADM_URL_${x86_tag}__|${_au}|g"
        -e "s|__ASADM_SHA_${x86_tag}__|${_as}|g"
        -e "s|__ASADM_URL_${arm_tag}__|${_cu}|g"
        -e "s|__ASADM_SHA_${arm_tag}__|${_cs}|g"
    )
}

# update_dockerfile target version single_arch
# Performs in-place update of an existing Dockerfile:
#   - Patches the version label.
#   - Removes stale ARG/COPY lines from prior formats.
#   - Removes vendored-tini COPY block (tini is now fetched at build time).
#   - Re-inlines the install logic as a RUN \ block with fresh URL/SHA values.
#   - Ensures STOPSIGNAL SIGTERM is present.
# Relies on caller-scoped: x86_link x86_sha arm_link arm_sha
function update_dockerfile() {
    local target=$1 version=$2 single_arch=$3
    local df="${target}/Dockerfile"

    log_info "    Updating in-place: ${df}"

    # Patch version label
    _sed_i "s|org.opencontainers.image.version=\"[^\"]*\"|org.opencontainers.image.version=\"${version}\"|" "${df}"

    # Refresh support files
    cp template/0/entrypoint.sh "${target}/"
    chmod +x "${target}/entrypoint.sh"
    cp template/7/aerospike.template.conf "${target}/"

    # Resolve install script source.
    local pkg_type install_script
    pkg_type=$(support_distro_to_pkg_type "$(basename "${target}")")
    install_script="${SCRIPT_DIR}/scripts/${pkg_type}/install-native.sh"
    _stage_local_packages "${target}" "${pkg_type}"

    # Remove vendored-tini COPY block (older Dockerfiles only; idempotent if absent).
    _dockerfile_remove_vendored_tini "${df}"

    # Sync the COPY instruction for local package builds:
    # - local files  → insert/keep   COPY *.{deb,rpm} /tmp/aerospike/
    # - remote URLs  → no COPY needed (curl downloads the file)
    _dockerfile_sync_native_copy "${df}" "$(_local_pkg_copy_glob "${pkg_type}")"

    # Re-inline install logic as RUN \ block; substitute package URL/SHA placeholders.
    _dockerfile_refresh_install_block "${df}" "${install_script}"

    # Clean trailing whitespace and ensure trailing newline.
    _sed_i 's/[[:space:]]*$//' "${df}"
    if [ -n "$(tail -c1 "${df}" 2>/dev/null)" ]; then
        echo >>"${df}"
    fi
}
