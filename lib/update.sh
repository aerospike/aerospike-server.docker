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
# Optional COPY_LINE: e.g. "COPY server_amd64.deb ... /tmp/" inserted before the install section.
function _dockerfile_refresh_install_block() {
    local df=$1
    local inst=$2
    local copy_line=${3:-}
    python3 - "$df" "$inst" "${copy_line}" <<'PY'
import pathlib, re, sys

df_path = pathlib.Path(sys.argv[1])
inst_path = pathlib.Path(sys.argv[2])
copy_line = sys.argv[3] if len(sys.argv) > 3 else ""
script = inst_path.read_text()
if not script.endswith("\n"):
    script += "\n"
prefix = (copy_line.rstrip() + "\n\n") if copy_line.strip() else ""
new_block = (
    prefix
    + "# Install Aerospike Server and Tools\n"
    + "# hadolint ignore=DL3003,DL3008,DL3041,SC2015\n"
    + "RUN bash <<'AEROSPIKE_INSTALL'\n"
    + script
    + "AEROSPIKE_INSTALL\n"
)
text = df_path.read_text()
# Strip prior local-pkg COPY lines; fresh ones come from copy_line above.
lines = [ln for ln in text.splitlines(True) if not re.match(r"^COPY server_", ln)]
text = "".join(lines)
text2, n_old = re.subn(
    r"(?ms)^# Install Aerospike Server and Tools\n"
    r"COPY install\.sh /tmp/install\.sh\n"
    r"# hadolint[^\n]*\n"
    r"RUN bash /tmp/install\.sh && rm -f /tmp/install\.sh\n",
    new_block,
    text,
    count=1,
)
if n_old == 0:
    text2, n_new = re.subn(
        r"(?ms)^# Install Aerospike Server and Tools\n.*?\nAEROSPIKE_INSTALL\n",
        new_block,
        text,
        count=1,
    )
    if n_new != 1:
        sys.stderr.write(f"{df_path}: could not replace install block (matched {n_new})\n")
        sys.exit(1)
if not text2.startswith("# syntax=docker/dockerfile:1"):
    text2 = "# syntax=docker/dockerfile:1\n" + text2
df_path.write_text(text2)
PY
}

function _sync_static_tini_to_target() {
    local target=$1
    mkdir -p "${target}/static/tini"
    cp "${SCRIPT_DIR}/static/tini/as-tini-static-amd64" "${SCRIPT_DIR}/static/tini/as-tini-static-arm64" "${target}/static/tini/"
}

# Insert vendored-tini COPY/RUN after SHELL if missing (matches lib/dockerfile_fragment_tini.docker).
function _dockerfile_ensure_vendored_tini() {
    local df=$1
    python3 - "${df}" "${SCRIPT_DIR}/lib/dockerfile_fragment_tini.docker" <<'PY'
import pathlib, sys

df_path = pathlib.Path(sys.argv[1])
frag_path = pathlib.Path(sys.argv[2])
frag = frag_path.read_text()
if not frag.endswith("\n"):
    frag += "\n"
text = df_path.read_text()
if "COPY static/tini/as-tini-static-amd64" in text:
    raise SystemExit(0)
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

    # Refresh install script
    local pkg_type
    pkg_type=$(support_distro_to_pkg_type "$(basename "${target}")")
    if [ "${pkg_type}" = "deb" ]; then
        cp scripts/deb/install.sh "${target}/install.sh"
    else
        cp scripts/rpm/install.sh "${target}/install.sh"
    fi
    chmod +x "${target}/install.sh"

    _sync_static_tini_to_target "${target}"
    _dockerfile_ensure_vendored_tini "${df}"

    # Re-embed install.sh (RUN heredoc); refresh local-pkg COPY prefix via copy_line.
    _dockerfile_refresh_install_block "${df}" "${target}/install.sh" "${copy_line}"

    # Clean trailing whitespace
    _sed_i 's/[[:space:]]*$//' "${df}"
    # Ensure trailing newline
    if [ -n "$(tail -c1 "${df}" 2>/dev/null)" ]; then
        echo >>"${df}"
    fi
}
