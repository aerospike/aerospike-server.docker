#!/usr/bin/env bash
# Create .sha256 files for all packages in an artifacts directory.
# Each package (e.g. foo.deb) gets foo.deb.sha256 with one line: "hash  filename"
# so the build can fetch link.sha256 and use the hash, and sha256sum -c can verify.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.

set -Eeuo pipefail

ARTIFACTS_DIR="${1:-artifacts}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

if [[ "${ARTIFACTS_DIR}" == /* ]]; then
    BASE="${ARTIFACTS_DIR}"
else
    BASE=$(cd "${REPO_ROOT}/${ARTIFACTS_DIR}" 2>/dev/null && pwd || true)
fi

if [ -z "${BASE}" ] || [ ! -d "${BASE}" ]; then
    echo "Usage: $0 [artifacts_dir]" >&2
    echo "  artifacts_dir defaults to 'artifacts' (relative to repo root)." >&2
    echo "  Directory not found: ${ARTIFACTS_DIR}" >&2
    exit 1
fi

# Prefer sha256sum (Linux), else shasum -a 256 (macOS); both output "hash  filename"
if command -v sha256sum >/dev/null 2>&1; then
    HASH_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    HASH_CMD="shasum -a 256"
else
    echo "Need sha256sum or shasum" >&2
    exit 1
fi

count=0
while IFS= read -r -d '' f; do
    [ -f "${f}" ] || continue
    case "${f}" in
    *.sha256) continue ;;
    *) ;;
    esac
    out="${f}.sha256"
    # Write "hash  filename" (basename only so verification works from same dir)
    b=$(basename "${f}")
    "${HASH_CMD}" "${f}" | (
        read -r hash rest
        echo "${hash}  ${b}"
    ) >"${out}"
    echo "${out}"
    count=$((count + 1))
done < <(find "${BASE}" -type f \( -name '*.deb' -o -name '*.rpm' -o -name '*.tgz' -o -name '*.tar.gz' \) -print0 2>/dev/null)

echo "Created ${count} .sha256 file(s) under ${BASE}"
