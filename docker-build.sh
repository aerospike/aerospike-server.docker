#!/usr/bin/env bash
#
# Generate and build Docker images for Aerospike server releases.
# Copyright 2014-2025 Aerospike, Inc. Licensed under the Apache License, Version 2.0.
# See LICENSE in the project root.
#
# Dependencies: lib/{log,support,version,fetch,emit,update,generate,bake}.sh
# Flow: parse args -> generate_dockerfiles -> [generate_bake -> build]
#
# Default mode (no -g): in-place update of existing Dockerfiles (ARGs, SHAs, links).
# With -g/--generate: full Dockerfile regeneration from scratch.
# Install logic lives in scripts/deb/install.sh and scripts/rpm/install.sh.
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
    --no-cache          Disable Docker build cache (force full rebuild)
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
    bake-multi.hcl                            Docker buildx bake file

MODES OF OPERATION:
    Without -g (default):
        Updates existing Dockerfiles in-place: patches ARG values (links, SHAs,
        version), refreshes support files (entrypoint.sh, install.sh, config).
        If a Dockerfile doesn't exist yet, auto-falls back to full generation.

    With -g:
        Full regeneration: removes releases/<lineage>/ dirs for the targeted
        lineage(s) and writes fresh Dockerfiles. Use after structural changes
        (new distro, new dependencies, install script rewrite, etc.).

EXAMPLES:
    # Build all editions/distros for lineage 8.1 (local test, in-place update)
    $0 -t 8.1

    # Build specific edition and distro
    $0 -t 8.1 -e enterprise -d ubuntu24.04

    # Build multiple editions and distros
    $0 -t 8.1 -e enterprise community -d ubuntu24.04 ubi9

    # Build for specific architecture(s) only
    $0 -t 8.1 -a amd64
    $0 -t 8.1 -a arm64
    $0 -p 8.1 -a amd64 arm64

    # Build and push to registry
    $0 -p 8.1 -e enterprise federal

    # Build and push to one or more registries
    $0 -p 8.1 -e enterprise -r artifact.aerospike.io/database-docker-dev-local
    $0 -p 8.1 -e enterprise -r reg1 -r reg2

    # Push with custom timestamp for tags (e.g. product:8.1.1.1-20250225120000)
    $0 -p 8.1 -T 20250225120000

    # Fully regenerate Dockerfiles only (no build)
    $0 -g 8.1

    # Build from custom/staging artifacts server
    $0 -t 8.1.1.0-start-108 -e enterprise -d ubi9 \\
       -u https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise

    # Build all supported lineages
    $0 -t
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
        --no-cache)
            bake_opts+=(--no-cache)
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
