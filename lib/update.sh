#!/usr/bin/env bash
# In-place Dockerfile update: patch ARGs, LABELs, and local-pkg COPY lines
# without regenerating the full Dockerfile.  Used by default (no -g flag).
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
# inst  = path to the source install script (scripts/deb/install.sh or rpm).
# The script is NOT copied into the build context — DOI rejects COPY of
# build-time-only scripts. Logic is inlined as a RUN \ block via the converter.
# Optional COPY_LINE: e.g. "COPY server_amd64.deb ... /tmp/" for local pkgs.
function _dockerfile_refresh_install_block() {
    local df=$1
    local inst=$2
    local copy_line=${3:-}

    # Temp files; cleaned up on function return (including on error).
    local nbf tmp
    nbf=$(mktemp)
    tmp=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '${nbf}' '${tmp}'" RETURN

    # Step A: build the new install block into a temp file.
    # Inline RUN \ block (DOI-accepted pattern):
    #   - No BuildKit heredoc (DOI parser cannot pre-scan them for build ordering).
    #   - No COPY install.sh (DOI's bashbrew build context only includes files
    #     present in the upstream directory; install.sh is not committed there).
    [ -n "${copy_line}" ] && printf '%s\n\n' "${copy_line}" > "${nbf}"
    _sh_to_dockerfile_run "${inst}" >> "${nbf}"
    # Ensure exactly one trailing blank line (separator before the next instruction).
    printf '\n' >> "${nbf}"

    # Step B: strip prior local-pkg COPY lines; fresh ones come from copy_line above.
    _sed_i '/^COPY server_/d' "${df}"

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
    ' "${df}" > "${tmp}" && mv "${tmp}" "${df}"

    # Step D: cleanup passes.
    # Remove BuildKit-only parser directive (DOI legacy builder does not use it).
    _sed_i '/^# syntax=docker\/dockerfile:/d' "${df}"
    # Remove STOPSIGNAL SIGTERM + optional following blank line.
    awk '/^STOPSIGNAL SIGTERM$/ {
        if ((getline nl) > 0 && nl != "") print nl
        next
    } { print }' "${df}" > "${tmp}" && mv "${tmp}" "${df}"
    # Remove ARG AEROSPIKE_COMPAT_LIBS="0" (kept only when value is "1").
    _sed_i '/^ARG AEROSPIKE_COMPAT_LIBS="0"$/d' "${df}"

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
            ' "${df}" > "${tmp}" && mv "${tmp}" "${df}"
        fi
    fi
    # Remove blank line between ENV AEROSPIKE_LINUX_BASE and the next ARG line
    # (DOI reference: they appear on consecutive lines).
    awk '/^ENV AEROSPIKE_LINUX_BASE=/ {
        print
        if ((getline nl) > 0) {
            if (nl == "") { getline nl }
            print nl
        }
        next
    } { print }' "${df}" > "${tmp}" && mv "${tmp}" "${df}"

    # Step F: ensure file starts with exactly one blank line; strip trailing whitespace.
    awk 'BEGIN{skip=1} skip && /^$/{next} {skip=0; print}' "${df}" \
        | { printf '\n'; cat; } > "${tmp}" && mv "${tmp}" "${df}"
    _sed_i 's/[[:space:]]*$//' "${df}"
}

function _sync_static_tini_to_target() {
    local target=$1
    mkdir -p "${target}/static/tini"
    cp "${SCRIPT_DIR}/static/tini/as-tini-static-amd64" "${SCRIPT_DIR}/static/tini/as-tini-static-arm64" "${target}/static/tini/"
}

# Ensure the vendored-tini block in the Dockerfile matches the canonical
# fragment (lib/dockerfile_fragment_tini.docker). Handles three cases:
#
#   1. Block missing entirely   -> insert fragment after the SHELL line.
#   2. Older-form block present -> replace whole block (leading comments +
#      COPY + optional `ARG TARGETARCH` + any-form RUN continuation ending
#      in `rm -rf /opt/aerospike-tini`) with the canonical fragment.
#   3. Canonical form already present -> regex still matches and writes the
#      same content back (no diff); safe idempotent replacement.
#
# Why the replacement style instead of point-patches:
#   The tini install step has moved through three shapes (BuildKit-only
#   `${TARGETARCH}`; `uname -m` fallback; now dpkg/rpm userspace detection)
#   to satisfy Docker Official Images policy. The regex anchors on the
#   stable endpoints (`COPY static/tini/...` and `rm -rf /opt/aerospike-tini`)
#   so one code path converts any prior shape to the current canonical one.
function _dockerfile_ensure_vendored_tini() {
    local df=$1
    local frag_file="${SCRIPT_DIR}/lib/dockerfile_fragment_tini.docker"

    # Read canonical fragment; ensure it ends with a newline.
    local frag
    frag=$(cat "${frag_file}")
    [[ "${frag}" != *$'\n' ]] && frag+=$'\n'

    local tmp
    tmp=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '${tmp}'" RETURN

    if grep -qF 'COPY static/tini/as-tini-static-amd64' "${df}"; then
        # The tini block has gone through multiple shapes:
        #   1. COPY-only (current form — tini arch-selection is now in install.sh)
        #   2. COPY + RUN if command -v dpkg ... rm -rf /opt/aerospike-tini (previous)
        #   3. COPY + ARG TARGETARCH + RUN case ... rm -rf /opt/aerospike-tini (oldest)
        # Awk state machine: consume all tini-related lines, emit canonical fragment once.
        awk -v frag="${frag}" -v src="${df}" '
        function emit_frag() { printf "%s", frag }
        BEGIN { state = "looking"; buf = ""; buf_n = 0 }

        state == "looking" {
            # Buffer contiguous comment lines — they might be the tini block header.
            if (/^#/) { buf = buf $0 "\n"; buf_n++; next }
            if (/^COPY static\/tini\/as-tini-static-amd64/) {
                # Discard buffered comments (they are the tini block header) + this line.
                buf = ""; buf_n = 0
                state = "after_copy"
                next
            }
            # Not a tini line: flush buffer and print this line.
            if (buf_n > 0) { printf "%s", buf; buf = ""; buf_n = 0 }
            print
            next
        }

        state == "after_copy" {
            if (/^#/)              { next }          # discard trailing tini comments
            if (/^ARG TARGETARCH/) { next }          # discard (older form)
            if (/^RUN /)           { state = "in_run"; next }
            # Next non-comment, non-ARG, non-RUN line: no RUN block (current form).
            emit_frag(); state = "done"; print; next
        }

        state == "in_run" {
            if (/rm -rf \/opt\/aerospike-tini/) { state = "after_run"; next }
            next  # discard RUN continuation lines
        }

        state == "after_run" {
            if (/^[ \t]/) { next }   # still in RUN continuation
            emit_frag(); state = "done"; print; next
        }

        state == "done" { print; next }

        { print }

        END {
            if (buf_n > 0) printf "%s", buf   # flush any unmatched buffered comments
            if (state == "after_copy" || state == "in_run" || state == "after_run") {
                # EOF reached while consuming tini block — emit fragment now.
                emit_frag()
            }
        }
        ' "${df}" > "${tmp}" && mv "${tmp}" "${df}"
    else
        # Block missing: insert canonical fragment after the SHELL [...] line.
        awk -v frag="${frag}" -v src="${df}" '
        BEGIN { inserted = 0 }
        !inserted && /^SHELL \[/ && /\]/ {
            print
            print ""
            printf "%s", frag
            inserted = 1
            next
        }
        { print }
        END {
            if (!inserted) {
                print src ": could not find SHELL line to insert vendored tini" \
                    > "/dev/stderr"
                exit 1
            }
        }
        ' "${df}" > "${tmp}" && mv "${tmp}" "${df}"
    fi
}

# resolve_packages distro edition version tools_version single_arch
# Outputs: x86_link x86_sha arm_link arm_sha pkg_format use_local_pkg
# Sets the six variables above in the caller's scope.
function resolve_packages() {
    local artifact_distro=$1 edition=$2 version=$3 tools_version=$4 single_arch=$5
    local pkg_type=$6

    x86_link=""
    x86_sha=""
    arm_link=""
    arm_sha=""
    # shellcheck disable=SC2034  # consumed by caller (generate.sh) via dynamic scoping
    pkg_format="tgz"
    use_local_pkg=""

    if [ -n "${tools_version}" ]; then
        x86_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
        x86_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64")
        arm_link=$(get_package_link "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
        arm_sha=$(fetch_package_sha "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64")
    fi

    if is_local_artifacts_dir; then
        local local_base="${ARTIFACTS_DOMAIN}"
        [[ "${local_base}" != /* ]] && [[ "${local_base}" != http* ]] && local_base="${SCRIPT_DIR}/${local_base}"
        [ -d "${local_base}" ] && local_base=$(
            cd "${local_base}" || exit 1
            pwd
        )
        local local_x86 local_arm
        local_x86=$(find_local_server_package "${local_base}" "${artifact_distro}" "${edition}" "${version}" "x86_64" "${pkg_type}")
        local_arm=$(find_local_server_package "${local_base}" "${artifact_distro}" "${edition}" "${version}" "aarch64" "${pkg_type}")
        if [ -n "${local_x86}" ] || [ -n "${local_arm}" ]; then
            # shellcheck disable=SC2034  # consumed by caller via dynamic scoping
            pkg_format="${pkg_type}"
            [ -n "${local_x86}" ] && x86_link="${local_x86}"
            [ -n "${local_arm}" ] && arm_link="${local_arm}"
            use_local_pkg="1"
        fi
    fi

    if [ -z "${use_local_pkg}" ] && [ -z "${x86_sha}" ]; then
        if ! is_local_artifacts_dir; then
            x86_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "x86_64" "${pkg_type}")
            x86_sha=$(fetch_sha_for_link "${x86_link}")
            if [ -n "${x86_link}" ]; then
                # shellcheck disable=SC2034  # consumed by caller via dynamic scoping
                pkg_format="${pkg_type}"
                arm_link=$(get_server_package_link_native "${artifact_distro}" "${edition}" "${version}" "${tools_version}" "aarch64" "${pkg_type}")
                arm_sha=$(fetch_sha_for_link "${arm_link}")
            fi
        fi
    fi

    if [ "${single_arch}" = "amd64" ]; then
        arm_link=""
        arm_sha=""
    fi
    if [ "${single_arch}" = "arm64" ]; then
        x86_link=""
        x86_sha=""
    fi
}

# prepare_local_packages target pkg_type x86_link arm_link
# Copies local packages + .sha256 into the context dir, returns updated
# x86_sha, arm_sha, and the COPY directive via copy_line (in caller scope).
function prepare_local_packages() {
    local target=$1 pkg_type=$2

    copy_line=""
    local copy_files=()

    local need_sha=false
    [ -n "${x86_link}" ] && [ ! -f "${x86_link}.sha256" ] && need_sha=true
    [ -n "${arm_link}" ] && [ ! -f "${arm_link}.sha256" ] && need_sha=true
    if [ "${need_sha}" = true ]; then
        local local_base="${ARTIFACTS_DOMAIN}"
        [[ "${local_base}" != /* ]] && [[ "${local_base}" != http* ]] && local_base="${SCRIPT_DIR}/${local_base}"
        [ -d "${local_base}" ] && local_base=$(
            cd "${local_base}" || exit 1
            pwd
        )
        if [ -d "${local_base}" ]; then
            log_info "    Creating missing .sha256 in ${local_base} (shasum-artifacts.sh)"
            "${SCRIPT_DIR}/scripts/shasum-artifacts.sh" "${local_base}" >/dev/null 2>&1 || true
        fi
    fi

    if [ "${pkg_type}" = "rpm" ]; then
        if [ -n "${x86_link}" ]; then
            cp "${x86_link}" "${target}/server_x86_64.rpm" && copy_files+=(server_x86_64.rpm)
            [ -f "${x86_link}.sha256" ] && cp "${x86_link}.sha256" "${target}/server_x86_64.rpm.sha256" && copy_files+=(server_x86_64.rpm.sha256) && x86_sha=$(awk '{print $1}' "${x86_link}.sha256")
        fi
        if [ -n "${arm_link}" ]; then
            cp "${arm_link}" "${target}/server_aarch64.rpm" && copy_files+=(server_aarch64.rpm)
            [ -f "${arm_link}.sha256" ] && cp "${arm_link}.sha256" "${target}/server_aarch64.rpm.sha256" && copy_files+=(server_aarch64.rpm.sha256) && arm_sha=$(awk '{print $1}' "${arm_link}.sha256")
        fi
    else
        if [ -n "${x86_link}" ]; then
            cp "${x86_link}" "${target}/server_amd64.deb" && copy_files+=(server_amd64.deb)
            [ -f "${x86_link}.sha256" ] && cp "${x86_link}.sha256" "${target}/server_amd64.deb.sha256" && copy_files+=(server_amd64.deb.sha256) && x86_sha=$(awk '{print $1}' "${x86_link}.sha256")
        fi
        if [ -n "${arm_link}" ]; then
            cp "${arm_link}" "${target}/server_arm64.deb" && copy_files+=(server_arm64.deb)
            [ -f "${arm_link}.sha256" ] && cp "${arm_link}.sha256" "${target}/server_arm64.deb.sha256" && copy_files+=(server_arm64.deb.sha256) && arm_sha=$(awk '{print $1}' "${arm_link}.sha256")
        fi
    fi

    [ ${#copy_files[@]} -gt 0 ] && copy_line="COPY ${copy_files[*]} /tmp/"
}

# update_dockerfile target version needs_compat_libs copy_line single_arch
# Performs sed-based in-place patching of version-specific values in an
# existing Dockerfile.  Also manages the COPY local-pkg line and
# AEROSPIKE_LOCAL_PKG ARG.
# Relies on caller-scoped: x86_link x86_sha arm_link arm_sha use_local_pkg
function update_dockerfile() {
    local target=$1 version=$2 needs_compat_libs=$3 copy_line=$4 single_arch=$5
    local df="${target}/Dockerfile"

    log_info "    Updating in-place: ${df}"

    # Patch version label
    _sed_i "s|org.opencontainers.image.version=\"[^\"]*\"|org.opencontainers.image.version=\"${version}\"|" "${df}"

    # Patch ARG values
    if [ "${single_arch}" != "arm64" ]; then
        _sed_i "s|^ARG AEROSPIKE_X86_64_LINK=.*|ARG AEROSPIKE_X86_64_LINK=\"${x86_link}\"|" "${df}"
        _sed_i "s|^ARG AEROSPIKE_SHA_X86_64=.*|ARG AEROSPIKE_SHA_X86_64=\"${x86_sha}\"|" "${df}"
    fi
    if [ "${single_arch}" != "amd64" ]; then
        _sed_i "s|^ARG AEROSPIKE_AARCH64_LINK=.*|ARG AEROSPIKE_AARCH64_LINK=\"${arm_link}\"|" "${df}"
        _sed_i "s|^ARG AEROSPIKE_SHA_AARCH64=.*|ARG AEROSPIKE_SHA_AARCH64=\"${arm_sha}\"|" "${df}"
    fi
    _sed_i "s|^ARG AEROSPIKE_COMPAT_LIBS=.*|ARG AEROSPIKE_COMPAT_LIBS=\"${needs_compat_libs}\"|" "${df}"

    # Manage AEROSPIKE_LOCAL_PKG ARG
    if [ -n "${use_local_pkg}" ]; then
        if grep -q '^ARG AEROSPIKE_LOCAL_PKG=' "${df}"; then
            _sed_i "s|^ARG AEROSPIKE_LOCAL_PKG=.*|ARG AEROSPIKE_LOCAL_PKG=\"1\"|" "${df}"
        else
            # Append after COMPAT_LIBS line (awk is portable; sed a\ is not on BSD)
            local tmpfile
            tmpfile=$(mktemp)
            awk '/^ARG AEROSPIKE_COMPAT_LIBS=/{print; print "ARG AEROSPIKE_LOCAL_PKG=\"1\""; next}{print}' "${df}" >"${tmpfile}" && mv "${tmpfile}" "${df}"
        fi
    else
        _sed_i '/^ARG AEROSPIKE_LOCAL_PKG=/d' "${df}"
    fi

    # Refresh support files
    cp template/0/entrypoint.sh "${target}/"
    chmod +x "${target}/entrypoint.sh"
    cp template/7/aerospike.template.conf "${target}/"

    # Resolve install script source (never copied into build context — inlined).
    local pkg_type install_script
    pkg_type=$(support_distro_to_pkg_type "$(basename "${target}")")
    if [ "${pkg_type}" = "deb" ]; then
        install_script="${SCRIPT_DIR}/scripts/deb/install.sh"
    else
        install_script="${SCRIPT_DIR}/scripts/rpm/install.sh"
    fi

    _sync_static_tini_to_target "${target}"
    _dockerfile_ensure_vendored_tini "${df}"

    # Re-inline install logic as RUN \ block; refresh local-pkg COPY prefix.
    _dockerfile_refresh_install_block "${df}" "${install_script}" "${copy_line}"

    # Clean trailing whitespace
    _sed_i 's/[[:space:]]*$//' "${df}"
    # Ensure trailing newline
    if [ -n "$(tail -c1 "${df}" 2>/dev/null)" ]; then
        echo >>"${df}"
    fi
}
