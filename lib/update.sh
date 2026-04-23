#!/usr/bin/env bash
# In-place Dockerfile update: patch ARGs, LABELs, and local-pkg COPY lines
# without regenerating the full Dockerfile.  Used by default (no -g flag).
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/log.sh, lib/support.sh, lib/fetch.sh

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
    python3 - "$df" "$inst" "${copy_line}" "${SCRIPT_DIR}" <<'PY'
import importlib.util, pathlib, re, sys

df_path   = pathlib.Path(sys.argv[1])
inst_path = sys.argv[2]
copy_line = sys.argv[3] if len(sys.argv) > 3 else ""
script_dir = sys.argv[4] if len(sys.argv) > 4 else "."

# Load the shared converter module (lib/sh_to_dockerfile_run.py).
_spec = importlib.util.spec_from_file_location(
    "sh_to_dockerfile_run",
    str(pathlib.Path(script_dir) / "lib" / "sh_to_dockerfile_run.py"),
)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)

# Inline RUN \ block (DOI-accepted pattern):
#   - No BuildKit heredoc (DOI parser cannot pre-scan them for build ordering).
#   - No COPY install.sh (DOI's bashbrew build context only includes the
#     files present in the upstream directory; install.sh is not committed).
prefix = (copy_line.rstrip() + "\n\n") if copy_line.strip() else ""
# Ensure new_block ends with exactly one blank line (separator before next instruction).
new_block = prefix + _mod.sh_to_dockerfile_run(pathlib.Path(inst_path).read_text())
new_block = new_block.rstrip("\n") + "\n\n"

text = df_path.read_text()
# Strip prior local-pkg COPY lines; fresh ones come from copy_line above.
lines = [ln for ln in text.splitlines(True) if not re.match(r"^COPY server_", ln)]
text = "".join(lines)

# Match and replace the install block in whichever form it currently is:
#   1. Inline RUN \ block (current form) — idempotent.
#   2. Classic COPY install.sh + RUN bash (previous form).
#   3. BuildKit heredoc (oldest form).
PATTERNS = [
    # 1. Inline RUN \ block — also consume any trailing blank lines to ensure
    #    exactly one separator line is written by new_block.
    r"(?ms)^# Install Aerospike Server and Tools\n"
    r"# hadolint[^\n]*\n"
    r"RUN \\\n"
    r"(?:[ \t][^\n]*\n)+"
    r"\n*",
    # 2. Classic COPY + RUN bash
    r"(?ms)^# Install Aerospike Server and Tools\n"
    r"COPY install\.sh /tmp/install\.sh\n"
    r"# hadolint[^\n]*\n"
    r"RUN bash /tmp/install\.sh && rm -f /tmp/install\.sh\n",
    # 3. BuildKit heredoc
    r"(?ms)^# Install Aerospike Server and Tools\n.*?\nAEROSPIKE_INSTALL\n",
]
text2, n = text, 0
for pat in PATTERNS:
    text2, n = re.subn(pat, new_block, text, count=1)
    if n == 1:
        break
if n != 1:
    sys.stderr.write(f"{df_path}: could not replace install block (matched {n})\n")
    sys.exit(1)
# Remove BuildKit-only parser directive (DOI legacy builder does not use BuildKit).
text2 = re.sub(r"^# syntax=docker/dockerfile:[^\n]*\n", "", text2)
# Remove STOPSIGNAL SIGTERM (not present in DOI-accepted reference Dockerfiles).
text2 = re.sub(r"^STOPSIGNAL SIGTERM\n\n?", "", text2, flags=re.MULTILINE)
# Remove ARG AEROSPIKE_COMPAT_LIBS="0" (reference omits it when value is 0;
# only keep it for 7.2/ubuntu24.04 where the value would be "1").
text2 = re.sub(r'^ARG AEROSPIKE_COMPAT_LIBS="0"\n', "", text2, flags=re.MULTILINE)
# Add ENV AEROSPIKE_LINUX_BASE if missing (DOI reference: after ARG EDITION, no
# blank line between it and the next ARG).
if "ENV AEROSPIKE_LINUX_BASE=" not in text2:
    m_from = re.search(r"^FROM (\S+)", text2, flags=re.MULTILINE)
    if m_from:
        base_img = m_from.group(1)
        # Consume the blank line that follows ARG EDITION (if any) so ENV and
        # the first ARG link appear on consecutive lines (matching reference).
        text2 = re.sub(
            r"^(ARG AEROSPIKE_EDITION=\"[^\"\n]*\"\n)(\n?)",
            lambda m: m.group(1) + f'\nENV AEROSPIKE_LINUX_BASE="{base_img}"\n',
            text2, count=1, flags=re.MULTILINE,
        )
# Remove any blank line between ENV AEROSPIKE_LINUX_BASE and the next ARG line
# (DOI reference: they appear on consecutive lines).
text2 = re.sub(
    r"^(ENV AEROSPIKE_LINUX_BASE=\"[^\"\n]*\")\n\n(ARG )",
    r"\1\n\2",
    text2, flags=re.MULTILINE,
)
# Ensure file starts with a single blank line (matching DOI reference format).
text2 = text2.lstrip("\n")
text2 = "\n" + text2
df_path.write_text(text2)
PY
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
    python3 - "${df}" "${SCRIPT_DIR}/lib/dockerfile_fragment_tini.docker" <<'PY'
import pathlib, re, sys

df_path = pathlib.Path(sys.argv[1])
frag_path = pathlib.Path(sys.argv[2])
frag = frag_path.read_text()
if not frag.endswith("\n"):
    frag += "\n"
text = df_path.read_text()

if "COPY static/tini/as-tini-static-amd64" in text:
    # The tini block has gone through multiple shapes:
    #   1. COPY-only (new form, since tini arch-selection moved to install.sh)
    #   2. COPY + `RUN if command -v dpkg...rm -rf /opt/aerospike-tini` (previous)
    #   3. COPY + `ARG TARGETARCH` + `RUN case...rm -rf /opt/aerospike-tini` (oldest)
    # Match all forms; the RUN block is optional so the new COPY-only form also
    # matches (idempotent replacement).
    pattern = re.compile(
        r"(?ms)"
        # leading tini-related comment lines (contiguous `# ...`)
        r"(?:^#[^\n]*\n)*"
        # the COPY line
        r"^COPY static/tini/as-tini-static-amd64[^\n]*\n"
        # optional comment lines and optional ARG TARGETARCH (older forms)
        r"(?:^#[^\n]*\n)*"
        r"(?:^ARG TARGETARCH(?:=[^\n]*)?\n)?"
        # optional RUN block (absent in the new COPY-only form)
        r"(?:"
        r"^RUN [^\n]*\n"
        r"(?:^[ \t][^\n]*\n)*?"
        r"^[ \t][^\n]*rm -rf /opt/aerospike-tini\n"
        r")?"
    )
    text2, n = pattern.subn(frag, text, count=1)
    if n != 1:
        sys.stderr.write(
            f"{df_path}: could not match existing tini block to replace "
            "(file format unexpected)\n"
        )
        sys.exit(1)
    df_path.write_text(text2)
    raise SystemExit(0)

# Block missing: insert fragment after the SHELL line.
lines = text.splitlines(keepends=True)
out = []
inserted = False
for line in lines:
    out.append(line)
    if inserted:
        continue
    if line.startswith("SHELL [") and "]" in line:
        out.append("\n")
        out.append(frag)
        inserted = True
if not inserted:
    sys.stderr.write(f"{df_path}: could not find SHELL line to insert vendored tini\n")
    sys.exit(1)
df_path.write_text("".join(out))
PY
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
