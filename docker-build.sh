#!/usr/bin/env bash
#
# Generate and build Docker images for Aerospike server releases.
# Copyright 2014-2025 Aerospike, Inc. Licensed under the Apache License, Version 2.0.
# See LICENSE in the project root.
#
# Dependencies: lib/{log,support,version,fetch,sh_to_dockerfile_run,emit,update,generate,bake}.sh
# Flow: parse args -> generate_dockerfiles -> [generate_bake -> build]
#
# Default mode (no -g): in-place update of existing Dockerfiles (version label, install block).
# With -g/--generate: full Dockerfile regeneration from scratch.
# Install logic lives in scripts/deb/install.sh and scripts/rpm/install.sh (inlined into Dockerfile).
#

set -Eeuo pipefail

SCRIPT_DIR=$(
    cd "$(dirname "${BASH_SOURCE[0]:-$0}")" || exit 1
    pwd
)
cd "${SCRIPT_DIR}" || exit 1

source lib/log.sh
source lib/support.sh
source lib/version.sh
source lib/fetch.sh
source lib/sh_to_dockerfile_run.sh
source lib/emit.sh
source lib/update.sh
source lib/generate.sh
source lib/bake.sh

BAKE_FILE="bake-multi.hcl"

function usage() {
    cat <<EOF
Usage: $0 -t|-p|-g [OPTIONS] [version|lineage]

Generate Dockerfiles and build Docker images for Aerospike server releases.

MODE (one required):
    -t               Test mode - build and load locally (single platform per arch)
    -p               Push mode - build and push to registry (multi-arch manifest)
    -g, --generate   Generate Dockerfiles only (no build); forces full regeneration

OPTIONS:
    -r, --registry REG  Container registry (and repo path) for push mode.
                        Image names: <REG>/aerospike-server[-edition]:<tag>
                        Multiple: repeat -r (e.g. -r reg1 -r reg2)
                        Default: aerospike (docker.io/aerospike/...)
                        Example: -r artifact.aerospike.io/database-docker-dev-local
    -u, --url URL       Custom artifacts URL
                        Default: https://download.aerospike.com/artifacts
                        If *.tgz is not found, falls back to *.rpm (el9/el10) or *.deb (ubuntu).
                        JFrog Artifactory RPM (el9/el10 layout):
                          https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local
                        DEB (flat layout): database-deb-prod-public-local or direct edition URL.
    -e, --edition ED    Filter edition(s): community, enterprise, federal
                        Can specify multiple: -e enterprise community
                        Default: all editions
    -d, --distro DIST   Filter distro(s): ubuntu22.04, ubuntu24.04, ubi9, ubi10
                        Prefix match: -d ubuntu (all Ubuntu), -d ubi (all UBI)
                        Can specify multiple: -d ubuntu24.04 ubi9
                        Default: all distros supported by lineage
    -a, --arch ARCH     Filter architecture(s): amd64, arm64 (or x86_64, aarch64)
                        Can specify multiple: -a amd64 arm64
                        Default: all platforms (linux/amd64, linux/arm64; federal is amd64 only)
    -T, --timestamp TS  Use TS for push tags (e.g. version-TS). Format: YYYYMMDDHHMMSS
                        Default: current UTC time
    -n, --revision N    Immutable build counter for extra tags: <version>_N and, with distros,
                        <version>-<distro>_N (e.g. 8.1.2.0_1, 8.1.2.0-ubuntu24.04_2). Non-negative
                        integer. Omitted by default. Applies to bake push/test tags only (-t / -p).
    --no-cache          Disable Docker build cache (force full rebuild)

    Bake file tags (bake-multi.hcl; only for -t / -p, not -g alone):
        By default, images are tagged with lineage, full version, and version-timestamp only.
        Use -n/--revision for extra immutable <version>_N tags (see above). Optional :latest-style
        tags are off unless you pass one of:

    --tag-latest        Always add extra tags: :latest or :latest-<distro_slug> on push targets,
                        and :latest-<arch> or :latest-<distro_slug>-<arch> on test targets.
    --auto-latest       Add those same extra tags only when the resolved build version equals
                        the newest GA across all support lineages (7.1, 7.2, 8.0, 8.1). Queries
                        artifact listings; use with -t or -p. Ignored if --tag-latest is set.
    --no-latest         Disable both (default). Use to override BAKE_TAG_LATEST_AUTO / FORCE env.

    -h, --help          Show this help message

VERSION/LINEAGE:
    (none)                         Build all supported lineages (7.1, 7.2, 8.0, 8.1)
    8.1                            Lineage - auto-detects latest 8.1.x version
    8.1.1.0                        Specific release version
    8.1.1.0-rc2                    Release candidate
    8.1.1.0-start-16               Development build
    8.1.1.0-start-16-gea126d3      Development build with git hash

DISTRO SUPPORT BY LINEAGE (default: all distros below; primary UBI is ubi9):
    7.1:       ubuntu22.04, ubi9
    7.2, 8.0:  ubuntu24.04, ubi9
    8.1+:      ubuntu24.04, ubi10

OUTPUT:
    releases/<lineage>/<edition>/<distro>/    Generated Dockerfiles
    bake-multi.hcl                            Docker buildx bake file (see -n, --tag-latest, --auto-latest)

MODES OF OPERATION:
    Without -g (default):
        Updates existing Dockerfiles in-place: patches version label, re-inlines
        install block with fresh package URLs/SHAs, refreshes support files.
        If a Dockerfile doesn't exist yet, auto-falls back to full generation.

    With -g:
        Full regeneration: removes releases/<lineage>/ dirs for the targeted
        lineage(s) and writes fresh Dockerfiles. Use after structural changes
        (new distro, new dependencies, install script rewrite, etc.).

EXAMPLES:
    # --- Basic: resolve latest patch for a lineage, update Dockerfiles, build ---
    $0 -t 8.1
    $0 -t 8.1 -e enterprise -d ubuntu24.04
    $0 -t 8.1 -e enterprise community -d ubuntu24.04 ubi9
    $0 -t 8.1 -a amd64
    $0 -t 8.1 -a arm64
    $0 -p 8.1 -e enterprise federal
    $0 -p 8.1 -e enterprise -r artifact.aerospike.io/database-docker-dev-local
    $0 -p 8.1 -e enterprise -r reg1 -r reg2
    $0 -t

    # --- bake-multi.hcl: optional :latest-style tags (default: off) ---
    # Always add e.g. ...:latest or ...:latest-ubuntu24-04 on push, ...:latest-amd64 on test
    $0 -p 8.1 --tag-latest
    $0 -t 8.1 -e community -d ubuntu24.04 --tag-latest
    # Add ...:latest* only if the built version equals newest GA across 7.1–8.1 (queries artifacts)
    $0 -t 8.1 --auto-latest
    $0 -p 8.1 --auto-latest
    # Explicitly disable (default); overrides BAKE_TAG_LATEST_* env if set
    $0 -p 8.1 --no-latest

    # --- bake-multi.hcl: timestamp and immutable revision _N (extra tags; default: no -n) ---
    # Push tags include ...:<version>-<TS> plus optional ...:<version>_N (single-distro filter)
    $0 -p 8.1 -e community -d ubuntu24.04 -T 20250225120000 -n 1
    # Multi-distro push also gets ...:<version>-<distro>_N (e.g. 8.1.2.0-ubuntu24.04_2)
    $0 -p 8.1 -n 2
    # Test load: extra tag ...:<version>_N-amd64 or ...:<version>-<distro>_N-amd64
    $0 -t 8.1 -e enterprise -d ubuntu24.04 -n 2

    # --- Regenerate Dockerfiles only (no bake / no docker build) ---
    $0 -g 8.1

    # --- Custom artifacts URL (e.g. staging) ---
    $0 -t 8.1.1.0-start-108 -e enterprise -d ubi9 \\
       -u https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise
EOF
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
function main() {
    local mode="" custom_url="" version_or_lineage=""
    local generate_only=false
    local full_generate=false
    local -a bake_opts=()
    local build_timestamp=""
    local immutable_revision=""
    local tag_latest_auto=0 tag_latest_force=0
    declare -ga REGISTRY_PREFIXES=()

    declare -ga EDITION_FILTERS=()
    declare -ga DISTRO_FILTERS=()
    declare -ga ARCH_FILTERS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -t)
            mode="test"
            shift
            ;;
        -p)
            mode="push"
            shift
            ;;
        -r | --registry)
            REGISTRY_PREFIXES+=("$2")
            shift 2
            ;;
        -g | --generate)
            full_generate=true
            shift
            ;;
        -u | --url)
            custom_url="$2"
            shift 2
            ;;
        -e | --edition)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                EDITION_FILTERS+=("$1")
                shift
            done
            ;;
        -d | --distro)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                DISTRO_FILTERS+=("$1")
                shift
            done
            ;;
        -a | --arch)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                ARCH_FILTERS+=("$1")
                shift
            done
            ;;
        -T | --timestamp)
            build_timestamp="$2"
            shift 2
            ;;
        -n | --revision)
            immutable_revision="$2"
            shift 2
            ;;
        --no-cache)
            bake_opts+=(--no-cache)
            shift
            ;;
        --tag-latest)
            tag_latest_force=1
            shift
            ;;
        --auto-latest)
            tag_latest_auto=1
            shift
            ;;
        --no-latest)
            tag_latest_auto=0
            tag_latest_force=0
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            log_warn "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            version_or_lineage="$1"
            shift
            ;;
        esac
    done

    if [ -n "${immutable_revision}" ]; then
        if ! [[ "${immutable_revision}" =~ ^[0-9]+$ ]]; then
            log_warn "-n/--revision must be a non-negative integer (got: ${immutable_revision})"
            exit 1
        fi
    fi

    # -g alone = generate-only; -g with -t/-p = full regenerate + build
    if [ "${full_generate}" = true ] && [ -z "${mode}" ]; then
        generate_only=true
    fi
    if [ "${full_generate}" = false ] && [ -z "${mode}" ]; then
        log_warn "Mode (-t, -p, or -g) required"
        usage
        exit 1
    fi

    [ ${#REGISTRY_PREFIXES[@]} -eq 0 ] && REGISTRY_PREFIXES=("aerospike")
    [ -n "${custom_url}" ] && export ARTIFACTS_DOMAIN="${custom_url}"

    # When using -t or -p without -g, combinable: generate_only stays false,
    # full_generate stays false -> in-place update mode.
    # With -g alone: generate_only=true, full_generate=true.
    # With -g -t or -g -p: full_generate=true, generate_only=false, builds after.

    # Step 1: Generate / update Dockerfiles
    generate_dockerfiles "${version_or_lineage}" "${full_generate}"

    echo ""
    log_info "Dockerfiles generated in releases/"

    # Step 2: Build (unless generate-only)
    if [ "${generate_only}" = true ]; then
        exit 0
    fi

    echo ""
    log_info "=== Building Images ==="

    export BAKE_TAG_LATEST_AUTO="${tag_latest_auto}"
    export BAKE_TAG_LATEST_FORCE="${tag_latest_force}"
    export BAKE_IMMUTABLE_REVISION="${immutable_revision}"
    if [ -n "${immutable_revision}" ]; then
        log_info "Bake immutable revision tags enabled: _${immutable_revision} (e.g. <version>_${immutable_revision})"
    fi
    generate_bake "${build_timestamp}"

    case "${mode}" in
    test)
        log_info "Building for local testing..."
        docker buildx bake -f "${BAKE_FILE}" test --progress plain --load "${bake_opts[@]}"
        ;;
    push)
        log_info "Building and pushing to registry/registries (${REGISTRY_PREFIXES[*]})..."
        docker buildx bake -f "${BAKE_FILE}" push --progress plain --push "${bake_opts[@]}"
        ;;
    esac

    echo ""
    log_info "Done!"
}

main "$@"
