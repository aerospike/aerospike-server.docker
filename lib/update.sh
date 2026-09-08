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
# inst       = path to the source install script.
# use_native = "true" when using native .deb/.rpm (no TGZ bundle).
# The script is NOT copied into the build context — DOI rejects COPY of
# build-time-only scripts. Logic is inlined as a RUN \ block via the converter.
# Package URL/SHA placeholders are substituted using caller-scoped variables:
#   x86_link  x86_sha  arm_link  arm_sha
#   asadm_x86_link  asadm_x86_sha  asadm_arm_link  asadm_arm_sha
# (all set by resolve_packages)
function _dockerfile_refresh_install_block() {
    local df=$1
    local inst=$2
    local use_native=${3:-false}

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
    _build_subst_args "${pkg_type}" "${use_native}"
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

    # Step E: inject ENV AEROSPIKE_LINUX_BASE after ARG AEROSPIKE_EDITION if missing.
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
    # Remove blank lines between ENV AEROSPIKE_LINUX_BASE and the next non-blank line
    # (DOI reference: ENV and SHELL appear on consecutive lines).
    awk '/^ENV AEROSPIKE_LINUX_BASE=/ {
        print
        if ((getline nl) > 0) {
            while (nl == "") { if ((getline nl) <= 0) break }
            print nl
        }
        next
    } { print }' "${df}" >"${tmp}" && mv "${tmp}" "${df}"

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
#   copy_glob  empty → remove any such COPY line (TGZ mode or remote-URL native mode).
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
        # Remove any stale COPY *.deb / COPY *.rpm line first (different glob or edition).
        _sed_i '/^COPY \*\.\(deb\|rpm\) \/tmp\/aerospike\//d' "${df}"
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
        # TGZ mode or remote-URL native: remove any native-copy line.
        _sed_i '/^COPY \*\.\(deb\|rpm\) \/tmp\/aerospike\//d' "${df}"
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

# resolve_packages distro edition version tools_version single_arch pkg_type
# Outputs: x86_link x86_sha arm_link arm_sha pkg_format use_native
#          asadm_x86_link asadm_x86_sha asadm_arm_link asadm_arm_sha (native path only)
# Sets the variables above in the caller's scope via dynamic scoping.
function resolve_packages() {
    local artifact_distro=$1 edition=$2 version=$3 tools_version=$4 single_arch=$5
    local pkg_type=$6

    x86_link=""
    x86_sha=""
    arm_link=""
    arm_sha=""
    asadm_x86_link=""
    asadm_x86_sha=""
    asadm_arm_link=""
    asadm_arm_sha=""
    # shellcheck disable=SC2034  # consumed by caller (generate.sh) via dynamic scoping
    asadm_unreadable=false
    # shellcheck disable=SC2034  # consumed by caller (generate.sh) via dynamic scoping
    pkg_format="tgz"
    # shellcheck disable=SC2034  # consumed by update_dockerfile via dynamic scoping
    use_native=false

    if [ -n "${tools_version}" ]; then
        x86_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
        x86_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
        arm_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
        arm_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
    fi

    if [ -z "${x86_sha}" ]; then
        # Probe both arches independently so a single-arch build (-a arm64) is
        # not abandoned when the other arch has no package.
        x86_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64" "${pkg_type}")
        x86_sha=$(fetch_sha_for_link "${x86_link}")
        arm_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64" "${pkg_type}")
        arm_sha=$(fetch_sha_for_link "${arm_link}")
        if [ -n "${x86_link}" ] || [ -n "${arm_link}" ]; then
            # shellcheck disable=SC2034  # consumed by caller and update_dockerfile
            pkg_format="${pkg_type}"
            # shellcheck disable=SC2034  # consumed by update_dockerfile
            use_native=true
            local _arc=0
            asadm_x86_link=$(get_asadm_package_link_native "${artifact_distro}" "x86_64" "${pkg_type}") || _arc=$?
            asadm_x86_sha=$(fetch_sha_for_link "${asadm_x86_link}")
            asadm_arm_link=$(get_asadm_package_link_native "${artifact_distro}" "aarch64" "${pkg_type}") || _arc=$?
            asadm_arm_sha=$(fetch_sha_for_link "${asadm_arm_link}")
            if [ "${_arc}" -eq "${AS_LIST_ERROR}" ]; then
                log_warn "The asadm source given with -A could not be read"
                # shellcheck disable=SC2034  # consumed by caller (generate.sh) via dynamic scoping
                asadm_unreadable=true
            fi
        fi
    fi

    drop_unchecksummed_arches

    if [ "${single_arch}" = "amd64" ]; then
        arm_link=""
        arm_sha=""
        asadm_arm_link=""
        asadm_arm_sha=""
    fi
    if [ "${single_arch}" = "arm64" ]; then
        x86_link=""
        x86_sha=""
        asadm_x86_link=""
        asadm_x86_sha=""
    fi
}

# _install_script_for pkg_type use_native
# The install script a target is built from. Native .deb/.rpm images use the
# -native variants, which take a pre-staged package or a URL; TGZ bundles use
# the standard ones.
function _install_script_for() {
    local pkg_type=$1 use_native=$2
    if "${use_native}"; then
        echo "${SCRIPT_DIR}/scripts/${pkg_type}/install-native.sh"
    else
        echo "${SCRIPT_DIR}/scripts/${pkg_type}/install.sh"
    fi
}

# _stage_local_packages target pkg_type use_native
#
# Purge stale packages from a build context and copy in the ones this run
# resolved locally, so `COPY *.deb` picks up exactly the current set. Reads the
# caller-scoped x86_link / arm_link / asadm_*_link that resolve_packages sets.
#
# The purge is unconditional: a target that was a native build last run and is a
# TGZ build now must not keep its old packages, and nothing else in the context
# matches these globs.
function _stage_local_packages() {
    local target=$1 pkg_type=$2 use_native=$3

    rm -f "${target}"/aerospike-server-*."${pkg_type}" \
        "${target}"/aerospike-tools-*."${pkg_type}" \
        "${target}"/aerospike-asadm[-_]*."${pkg_type}" 2>/dev/null || true

    "${use_native}" || return 0

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

# _build_subst_args pkg_type use_native
#
# Fill the global SUBST_ARGS array with the sed expressions that replace the
# URL/SHA placeholders in an install script. One definition of which
# placeholders exist, shared by the generate path (which pipes through sed) and
# the update path (which passes them to _sed_i) -- previously two lists of eight
# expressions that had to be edited together and did not have to agree.
#
# An empty URL is meaningful: the native scripts read it as "the package was
# staged via COPY, do not download". Only an http link is substituted, so a
# local build always emits the empty form.
function _build_subst_args() {
    local pkg_type=$1 use_native=$2
    local x86_tag arm_tag
    if [ "${pkg_type}" = "deb" ]; then
        x86_tag="AMD64"
        arm_tag="ARM64"
    else
        x86_tag="X86_64"
        arm_tag="AARCH64"
    fi

    SUBST_ARGS=()
    if ! "${use_native}"; then
        SUBST_ARGS=(
            -e "s|__PKG_URL_${x86_tag}__|${x86_link:-}|g"
            -e "s|__PKG_SHA_${x86_tag}__|${x86_sha:-}|g"
            -e "s|__PKG_URL_${arm_tag}__|${arm_link:-}|g"
            -e "s|__PKG_SHA_${arm_tag}__|${arm_sha:-}|g"
        )
        return
    fi

    local _su="" _ss="" _au="" _as="" _bu="" _bs="" _cu="" _cs=""
    [[ "${x86_link:-}" == http* ]] && _su="${x86_link}" && _ss="${x86_sha:-}"
    [[ "${arm_link:-}" == http* ]] && _bu="${arm_link}" && _bs="${arm_sha:-}"
    [[ "${asadm_x86_link:-}" == http* ]] && _au="${asadm_x86_link}" && _as="${asadm_x86_sha:-}"
    [[ "${asadm_arm_link:-}" == http* ]] && _cu="${asadm_arm_link}" && _cs="${asadm_arm_sha:-}"
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
    # use_native is set by resolve_packages (caller-scoped) when no TGZ bundle found.
    local pkg_type install_script
    pkg_type=$(support_distro_to_pkg_type "$(basename "${target}")")
    local _use_native="${use_native:-false}"
    install_script=$(_install_script_for "${pkg_type}" "${_use_native}")
    _stage_local_packages "${target}" "${pkg_type}" "${_use_native}"

    # Remove vendored-tini COPY block (older Dockerfiles only; idempotent if absent).
    _dockerfile_remove_vendored_tini "${df}"

    # Sync the COPY instruction for local native package builds:
    # - use_native + local files  → insert/keep   COPY *.{deb,rpm} /tmp/aerospike/
    # - use_native + remote URLs  → no COPY needed (curl downloads the file)
    # - TGZ mode                  → remove any stale COPY *.deb/rpm line
    local _copy_glob=""
    if "${_use_native}"; then
        local _pkg
        for _pkg in "${x86_link:-}" "${arm_link:-}" \
            "${asadm_x86_link:-}" "${asadm_arm_link:-}"; do
            [[ "${_pkg}" != http* ]] && [ -n "${_pkg}" ] && _copy_glob="*.${pkg_type}"
        done
    fi
    _dockerfile_sync_native_copy "${df}" "${_copy_glob}"

    # Re-inline install logic as RUN \ block; substitute package URL/SHA placeholders.
    _dockerfile_refresh_install_block "${df}" "${install_script}" "${_use_native}"

    # Clean trailing whitespace and ensure trailing newline.
    _sed_i 's/[[:space:]]*$//' "${df}"
    if [ -n "$(tail -c1 "${df}" 2>/dev/null)" ]; then
        echo >>"${df}"
    fi
}
