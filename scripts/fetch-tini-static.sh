#!/usr/bin/env bash
# Download vendored as-tini-static binaries into static/tini/ (maintainer refresh).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}/static/tini" || exit 1
curl -fsSL -o as-tini-static-amd64 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static"
curl -fsSL -o as-tini-static-arm64 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64"
chmod +x as-tini-static-amd64 as-tini-static-arm64
echo "SHA256:"
sha256sum as-tini-static-amd64 as-tini-static-arm64
echo "Compare with static/tini/SOURCES.txt"
