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
    -u, --url URL       Where to get the server package. URL, local directory,
                        or a single local .deb/.rpm file.
                        Default: https://download.aerospike.com/artifacts
                        See PACKAGE SOURCES below for every accepted form.
    -A, --asadm-url URL Where to get the standalone aerospike-asadm package.
                        Default: the JFrog repo matching the package format.
                        Native .deb/.rpm builds only - the *.tgz bundles already
                        ship asadm inside aerospike-tools.
                        See PACKAGE SOURCES below.
    --no-asadm          Do not install a standalone aerospike-asadm package.
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

PACKAGE SOURCES (-u for the server, -A for asadm):

  How a server package is chosen:
    1. The *.tgz bundle (server + aerospike-tools, which includes asadm).
    2. If no *.tgz is found, the native .deb/.rpm for the distro. Tools are not
       in that bundle, so asadm is fetched separately via -A.
    Each arch is resolved independently: -a arm64 works even when only an arm64
    package exists.

  -u accepts:
    https://download.aerospike.com/artifacts        (default)
        <base>/aerospike-server-<edition>/<version>/<pkg>
    A direct edition URL
        e.g. https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise
        <base>/<version>/<pkg>
    A JFrog Artifactory repo (auto-detected; native packages only)
        RPM  <base>/<el9|el10>/<x86_64|aarch64>/<pkg>.rpm
             https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local
        DEB  <base>/pool/<suite>/<pkg-name>/<pkg>.deb   (apt dists/ + pool/)
             https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local
        Exact filenames (including the package revision, e.g. 8.1.2.4-4) and
        SHA256 checksums are discovered from the repo.
    A local directory (no download; packages are staged via COPY)
        Searched, in order:  <dir>/  <dir>/<version>/  <dir>/<lineage>/
                             <dir>/<lineage>/<version>/
                             <dir>/aerospike-server-<edition>/[<version>/]
        then recursively. Matches are version-aware, so stale packages from an
        earlier run are never picked up.
    A single local .deb/.rpm file
        Used when its filename names the requested package type, edition,
        version, distro and arch. With a lineage (8.1) rather than a full
        version, the version is read from the filename.

  -A accepts the same shapes, resolved to the newest matching package:
    A JFrog Artifactory repo         (default, chosen by package format:
                                      database-deb-prod-public-local for .deb,
                                      database-rpm-prod-public-local for .rpm)
    A plain HTTP directory index     packages sitting directly in that directory
    A local directory                staged via COPY, no download
    A direct .deb/.rpm URL or path   applied only to the arch its filename names,
                                     so one -A package cannot land in the other
                                     arch's image

  asadm source precedence:
    1. --no-asadm                          -> no asadm installed
    2. -A URL                              -> that source
    3. a local -u path, with no -A         -> that path only; nothing is fetched,
                                              even when it holds no asadm package
    4. otherwise                           -> the JFrog default for the package format
    Both arch spellings are accepted throughout (amd64/x86_64, arm64/aarch64).
    When no asadm package is found the image is built without it - a warning,
    not an error. A local -A path that does not exist is reported by name.

ENVIRONMENT (each is the default for the matching flag):
    ARTIFACTS_DOMAIN        same as -u
    ASADM_DOMAIN            same as -A
    ASADM_DOMAIN_DEB        asadm default for .deb builds
    ASADM_DOMAIN_RPM        asadm default for .rpm builds
    ASADM_DISABLED=true     same as --no-asadm
    BAKE_TAG_LATEST_FORCE=1 same as --tag-latest
    BAKE_TAG_LATEST_AUTO=1  same as --auto-latest
    DEBUG=true              log every artifact URL fetched
    LOG_COLOR=false         disable coloured log output

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
    $0 -g                                    # every lineage, every edition/distro

    # --- Custom artifacts URL (e.g. staging) ---
    $0 -t 8.1.1.0-start-108 -e enterprise -d ubi9 \\
       -u https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise

    # --- Native packages from JFrog (no *.tgz there; asadm once published) ---
    $0 -t 8.1 -e enterprise -d ubuntu24.04 \\
       -u https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local
    $0 -t 8.1 -e enterprise -d ubi10 \\
       -u https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local

    # --- Local packages: directory, or one specific file ---
    # Directory holding the server package (and optionally an asadm package)
    $0 -t 8.1.2.5 -e enterprise -d ubuntu -a arm64 -u ~/Downloads
    # A single .deb; version is read from the filename when given a lineage
    $0 -t 8.1 -e enterprise -d ubuntu -a arm64 \\
       -u ~/Downloads/aerospike-server-enterprise_8.1.2.5-9ubuntu24.04_arm64.deb

    # --- Choosing where asadm comes from ---
    # Server from JFrog, asadm from one specific package
    $0 -t 8.1 -e enterprise -d ubuntu24.04 \\
       -u https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local \\
       -A ~/Downloads/aerospike-asadm_5.0.3-4ubuntu24.04_aarch64.deb
    # Both from the same local directory
    $0 -t 8.1.2.5 -e enterprise -u ../signed-artifacts -A ../signed-artifacts
    # Build without asadm
    $0 -t 8.1 --no-asadm
EOF
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
function main() {
    local mode="" custom_url="" asadm_url="" version_or_lineage=""
    local no_asadm=false
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
        -A | --asadm-url)
            asadm_url="$2"
            shift 2
            ;;
        --no-asadm)
            no_asadm=true
            shift
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
    [ -n "${asadm_url}" ] && export ASADM_DOMAIN="${asadm_url}"
    [ "${no_asadm}" = true ] && export ASADM_DISABLED=true

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

    # A push must be all-or-nothing. Skipped targets are now omitted from the
    # bake file rather than built from their stale committed Dockerfile, so
    # without this a single failed package listing would quietly publish a
    # partial matrix at exit 0. -t is left alone: building the subset that did
    # resolve is the point of a local test run.
    if [ "${mode}" = "push" ] && [ "${G_SKIPPED_COUNT:-0}" -ne 0 ]; then
        log_warn "${G_SKIPPED_COUNT} target(s) were skipped - refusing to push a partial matrix."
        log_warn "Re-run with -t to build what did resolve, or fix the skipped targets first."
        exit 1
    fi

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
