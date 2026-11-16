#!/usr/bin/env bash
#
# Functional tests for Aerospike server Docker images.
# Copyright 2014-2025 Aerospike, Inc. Licensed under the Apache License, Version 2.0.
# See LICENSE in the project root.
#
# Dependencies: lib/log.sh, lib/support.sh, lib/version.sh
# Tag format must match docker-build.sh (single-distro: version-arch; multi: version-distro-arch).
#

set -Eeuo pipefail

source lib/log.sh
source lib/support.sh
source lib/version.sh

function usage() {
    cat <<EOF
Usage: $0 [version|lineage] [OPTIONS]
       $0 -i IMAGE [OPTIONS]

Functional tests for Aerospike server Docker images.

MODES:
    Test from releases/    Run docker-build.sh first, then test built images.
                           One version or lineage per run (e.g. 7.1 or 8.1).
                           To test multiple lineages, run the script once per lineage.
    Test specific image    Use -i to test any image by tag (local or remote)

OPTIONS:
    -i, --image IMAGE    Test a specific image by its full tag
    -e, --edition ED     Edition filter: community, enterprise, federal
                         With -i: optional, used to verify edition matches
                         Without -i: filters which images to test
    -d, --distro DIST    Distro filter: ubuntu22.04, ubuntu24.04, ubi9, ubi10
                         Prefix match: -d ubuntu (all Ubuntu), -d ubi (all UBI)
    -p, --platform PLAT  Platform: linux/amd64, linux/arm64 (single; overrides -a)
                         Default: auto-detect from host architecture
    -a, --arch ARCH      Architecture filter(s): amd64, arm64 (or x86_64, aarch64)
                         Can specify multiple: -a amd64 arm64. Test each built image for these archs.
                         Ignored when -i or -p is used.
    -c, --clean          Remove each image after its test passes (container + image)
    -s, --snyk           Run Snyk container scan on each image after tests pass
                         Requires snyk CLI in PATH. Results saved to
                         aerospike-server[-edition]-version[-distro]-arch-ts.snyk
    -h, --help           Show this help message

TESTS PERFORMED:
    1. Container starts successfully
    2. asd process is running
    3. asinfo exists in container
    4. asinfo responds with "ok"
    5. Version matches expected (if detectable)
    6. Edition matches expected (if -e specified)
    7. Default namespace 'test' exists
    8. Server arguments are forwarded to asd
    9. Non-option command is exec'd as given
    10. FEATURE_KEY_FILE is added to a custom --config-file (Enterprise/Federal only)
    11. Snyk container scan (optional, with -s/--snyk)

EXAMPLES:
    # Test a specific image (from any registry)
    $0 -i aerospike/aerospike-server-enterprise:8.1.1.0

    # Test a specific image with explicit platform
    $0 -i aerospike/aerospike-server:8.1.1.0 -p linux/arm64

    # Test a specific image and verify edition
    $0 -i myregistry/aerospike:latest -e enterprise

    # Test images built by docker-build.sh (from releases/ directory)
    # First: ./docker-build.sh -t 8.1 -e enterprise -d ubuntu24.04
    # Then:
    $0 8.1 -e enterprise -d ubuntu24.04

    # Test all built images for a lineage
    $0 8.1

    # Test only specific architecture(s) of built images
    $0 8.1 -a amd64
    $0 8.1 -a amd64 arm64

    # Test and cleanup images after
    $0 8.1 -e enterprise -c

    # Test with Snyk container security scan
    $0 8.1 -e enterprise --snyk

    # Test specific version (uses releases/ directory)
    $0 8.1.1.0-start-108 -e enterprise -d ubuntu24.04

PREREQUISITES:
    For testing from releases/:
      - Run docker-build.sh first to generate and build images
      - Images must be loaded locally (use -t mode in docker-build.sh)

    For testing specific images (-i):
      - Image must be accessible (local or pullable from registry)
EOF
}

function parse_args() {
    VERSION_OR_LINEAGE=""
    SPECIFIC_IMAGE=""
    EDITION=""
    DISTRIBUTION=""
    PLATFORM=""
    PLATFORM_EXPLICIT="false"
    declare -ga ARCH_FILTERS=()
    CLEAN="false"
    SNYK_SCAN="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -i | --image)
            SPECIFIC_IMAGE="$2"
            shift 2
            ;;
        -e | --edition)
            EDITION="$2"
            shift 2
            ;;
        -d | --distro)
            DISTRIBUTION="$2"
            shift 2
            ;;
        -p | --platform)
            PLATFORM="$2"
            PLATFORM_EXPLICIT="true"
            shift 2
            ;;
        -a | --arch)
            shift
            while [[ $# -gt 0 && ! "$1" =~ ^- ]]; do
                ARCH_FILTERS+=("$1")
                shift
            done
            ;;
        -c | --clean)
            CLEAN="true"
            shift
            ;;
        -s | --snyk)
            SNYK_SCAN="true"
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
            VERSION_OR_LINEAGE="$1"
            shift
            ;;
        esac
    done

    # Default platform to host architecture
    if [ -z "${PLATFORM}" ]; then
        local arch
        arch=$(uname -m)
        case "${arch}" in
        x86_64) PLATFORM="linux/amd64" ;;
        arm64 | aarch64) PLATFORM="linux/arm64" ;;
        *) PLATFORM="linux/amd64" ;;
        esac
    fi

    # Build PLATFORMS_LIST for test_from_releases: -p wins (single), else -a (multiple), else default (single)
    declare -ga PLATFORMS_LIST=()
    if [ "${PLATFORM_EXPLICIT}" = "true" ]; then
        PLATFORMS_LIST=("${PLATFORM}")
    elif [ ${#ARCH_FILTERS[@]} -gt 0 ]; then
        for f in "${ARCH_FILTERS[@]}"; do
            case "${f}" in
            amd64 | x86_64) PLATFORMS_LIST+=("linux/amd64") ;;
            arm64 | aarch64) PLATFORMS_LIST+=("linux/arm64") ;;
            *) log_warn "Unknown arch filter: $f (use amd64 or arm64)" ;;
            esac
        done
        if [ ${#PLATFORMS_LIST[@]} -eq 0 ]; then
            PLATFORMS_LIST=("${PLATFORM}")
        fi
    else
        PLATFORMS_LIST=("${PLATFORM}")
    fi

    if [ -z "${SPECIFIC_IMAGE}" ] && [ -z "${VERSION_OR_LINEAGE}" ]; then
        log_warn "Either version/lineage or -i IMAGE is required"
        usage
        exit 1
    fi
}

function get_version_from_dockerfile() {
    local dockerfile="releases/$1/$2/$3/Dockerfile"
    [ -f "${dockerfile}" ] || return 1
    sed -n 's/.*org.opencontainers.image.version="\([^"]*\)".*/\1/p' "${dockerfile}" | head -1 | tr -d '\r\n'
}

# Get image tag from bake-multi.hcl if present (matches what docker-build.sh -t produced, including -r registry)
function get_image_tag_from_bake() {
    local lineage=$1 edition=$2 distro=$3 arch=$4
    local bake_file="bake-multi.hcl"
    [ -f "${bake_file}" ] || return 1
    local tag_base="${lineage//./-}_${edition}_${distro//./-}_${arch}"
    sed -n "/target \"${tag_base}\"/,/^}/p" "${bake_file}" | sed -n 's/.*tags=\["\([^"]*\)".*/\1/p' | head -1
}

function run_docker() {
    log_info "Starting container..."
    if [ -n "${PLATFORM}" ]; then
        docker run -td --name "${CONTAINER}" -e "DEFAULT_TTL=30d" --platform="${PLATFORM}" "${IMAGE_TAG}"
    else
        docker run -td --name "${CONTAINER}" -e "DEFAULT_TTL=30d" "${IMAGE_TAG}"
    fi
}

function try() {
    local attempts=$1
    shift
    for ((i = 0; i < attempts; i++)); do
        if eval "${*@Q}" 2>/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}

# Attempts for the asd-startup polls (one try attempt ~= one second). When the
# image's architecture is not the host's — CI tests arm64 images on amd64
# runners — asd starts through the qemu binfmt handler, which multiplies
# startup time enough that the enterprise arm64 leg missed a 15s window while
# the very same image passed its other checks seconds earlier. Native runs
# keep the tight window so a genuinely broken image still fails fast.
function asd_wait_attempts() {
    local host image_arch="${PLATFORM#*/}"
    host=$(uname -m)
    case "${host}:${image_arch}" in
    x86_64:amd64 | aarch64:arm64 | arm64:arm64 | "${host}:") echo 15 ;;
    *) echo 60 ;;
    esac
}

function check_container() {
    local version=$1
    local expected_edition=$2
    local expected_arch=${3:-}
    local dockerfile=${4:-}

    log_info "Verifying container..."

    # Check running
    if [ "$(docker container inspect -f '{{.State.Status}}' "${CONTAINER}")" != "running" ]; then
        log_failure "Container failed to start"
        docker logs "${CONTAINER}" 2>&1 | tail -20
        exit 1
    fi
    log_success "Container running"

    # /licenses/LICENSE is a Red Hat UBI certification requirement and is
    # copied from the package's /opt/aerospike/doc/LICENSE by the install
    # script. Checked here rather than left to the install script alone: an
    # image that silently ships an empty /licenses/ is indistinguishable from a
    # good one on a green run, and this covers the deb images too.
    if docker exec -t "${CONTAINER}" test -s /licenses/LICENSE; then
        log_success "/licenses/LICENSE present"
    else
        log_failure "/licenses/LICENSE missing (Red Hat UBI certification)"
        exit 1
    fi

    # asadm is installed from its own package, selected by the install step's
    # arch-qualified glob. A package that glob misses is copied in and skipped
    # silently, so the image builds green without it. Asserted only when the
    # Dockerfile names a remote asadm: --no-asadm is a sanctioned build, and a
    # locally staged asadm leaves no trace in the Dockerfile to key on.
    if [ -n "${dockerfile}" ] && grep -q "asadmUrl='http" "${dockerfile}" 2>/dev/null; then
        if docker exec -t "${CONTAINER}" bash -c 'command -v asadm' >/dev/null 2>&1; then
            log_success "asadm found"
        else
            log_failure "asadm missing, but ${dockerfile} installs it"
            exit 1
        fi
    fi

    # Check asinfo exists before using it (used for "asd running" check when procps not in image)
    local have_asinfo=false
    if docker exec -t "${CONTAINER}" bash -c 'command -v asinfo' >/dev/null 2>&1; then
        log_success "asinfo found"
        have_asinfo=true
    else
        log_warn "asinfo not found in container; skipping asinfo-based checks"
    fi

    # Verify asd is running: prefer asinfo -v status (works without procps); else pgrep; else TCP port 3000
    local asd_ok=false attempts
    attempts=$(asd_wait_attempts)
    if [ "${have_asinfo}" = "true" ]; then
        if try "${attempts}" docker exec -t "${CONTAINER}" bash -c 'asinfo -v status' 2>/dev/null | grep -qE "^ok"; then
            asd_ok=true
        fi
    fi
    if [ "${asd_ok}" = false ] && try "${attempts}" docker exec -t "${CONTAINER}" bash -c 'pgrep -x asd' >/dev/null 2>&1; then
        asd_ok=true
    fi
    if [ "${asd_ok}" = false ] && try "${attempts}" docker exec -t "${CONTAINER}" bash -c 'echo >/dev/tcp/127.0.0.1/3000' 2>/dev/null; then
        asd_ok=true
    fi
    if [ "${asd_ok}" = false ]; then
        log_failure "asd not running"
        docker logs "${CONTAINER}" 2>&1 | tail -30
        exit 1
    fi
    log_success "asd running"

    if [ "${have_asinfo}" = "true" ]; then
        if ! docker exec -t "${CONTAINER}" bash -c 'asinfo -v status' 2>/dev/null | grep -qE "^ok"; then
            log_failure "asinfo not responding"
            exit 1
        fi
        log_success "asinfo responding"

        # Check version (optional)
        local base_version
        base_version=$(echo "${version}" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
        if [ -n "${base_version}" ]; then
            local build
            build=$(docker exec -t "${CONTAINER}" bash -c 'asinfo -v build' 2>/dev/null | tr -d '\r' || true)
            if [[ "${build}" == ${base_version}* ]]; then
                log_success "Version: ${build}"
            else
                log_info "Version: ${build}"
            fi
        fi

        # Check edition
        local actual_edition
        actual_edition=$(docker exec -t "${CONTAINER}" bash -c 'asinfo -v edition' 2>/dev/null | tr -d '\r' || true)

        if [ -n "${expected_edition}" ]; then
            # Edition was specified - verify it matches
            if [[ "${actual_edition,,}" == *"${expected_edition,,}"* ]]; then
                log_success "Edition: ${actual_edition}"
            else
                log_warn "Edition mismatch! Expected: ${expected_edition}, Got: ${actual_edition}"
            fi
        else
            # Edition not specified - just show it
            log_info "Edition: ${actual_edition}"
        fi

        # Report architecture (expected arch or container uname -m) — after Edition
        if [ -n "${expected_arch}" ] && [ "${expected_arch}" != "(host)" ]; then
            log_success "Architecture: ${expected_arch}"
        else
            local container_arch
            container_arch=$(docker exec -t "${CONTAINER}" uname -m 2>/dev/null | tr -d '\r\n' || echo "?")
            log_success "Architecture: ${container_arch}"
        fi

        # Check namespace
        if docker exec -t "${CONTAINER}" bash -c 'asinfo -v namespaces' 2>/dev/null | grep -q "test"; then
            log_success "Namespace 'test' exists"
        fi
    else
        # No asinfo — still report architecture
        if [ -n "${expected_arch}" ] && [ "${expected_arch}" != "(host)" ]; then
            log_success "Architecture: ${expected_arch}"
        else
            local container_arch
            container_arch=$(docker exec -t "${CONTAINER}" uname -m 2>/dev/null | tr -d '\r\n' || echo "?")
            log_success "Architecture: ${container_arch}"
        fi
    fi
}

# Print the argv of the asd server process running in container $1, polling
# until it appears. Returns 1 when no asd server process is found in time.
# PID 1 is tini, so asd is located by scanning /proc (procps may not be in image).
function asd_argv() {
    local container=$1

    # Single quotes are deliberate: this runs under "bash -c" inside the container,
    # so $p and the command substitution must reach it unexpanded.
    #
    # An asd whose cmdline is still empty counts as not found yet. Under qemu
    # emulation the process can show comm "asd" before /proc/<pid>/cmdline is
    # readable, so accepting the first comm match and reading the cmdline in a
    # second, unretried call failed the enterprise arm64 leg seconds into the
    # window (SERVER-2021).
    #
    # So does the entrypoint's own "asd --version" edition probe, which runs before
    # it execs the server: under emulation it lives long enough to be captured, and
    # was, on both arm64 legs. A server argv never carries --version (asd prints
    # and exits), so such a process is passed over and the poll goes on.
    # shellcheck disable=SC2016
    local find_asd='for p in /proc/[0-9]*; do { read -r n <"$p/comm"; } 2>/dev/null || continue; [ "$n" = asd ] || continue; c=$(tr "\0" " " <"$p/cmdline" 2>/dev/null); case "$c" in "" | *" --version "*) continue ;; esac; printf "%s" "$c"; exit 0; done; exit 1'

    # The capture is the poll: one call both finds asd and reads its argv, retried
    # until it returns something. "|| true": a failed exec (asd not up yet, or
    # exited) must not trip errexit before the caller's cleanup.
    local cmdline="" attempt attempts
    attempts=$(asd_wait_attempts)
    for ((attempt = 0; attempt < attempts; attempt++)); do
        cmdline=$(docker exec "${container}" bash -c "${find_asd}" 2>/dev/null | tr -d '\r') || true
        [ -n "${cmdline}" ] && break
        sleep 1
    done

    [ -n "${cmdline}" ] || return 1

    # When the image's architecture is emulated (CI tests arm64 images on amd64
    # runners), binfmt prefixes argv with the emulator and the target binary:
    #   /usr/bin/qemu-aarch64 /usr/bin/asd asd --early-verbose --fgdaemon
    # Strip that prefix so the comparison below still anchors on the real argv[0].
    # Do not relax it to a substring match instead: "/usr/bin/asd --early-verbose"
    # would satisfy a bare "asd --early-verbose" even with no asd prepended.
    local argv="${cmdline}"
    if [[ "${argv}" == /*qemu-* ]]; then
        argv="${argv#* }" # drop emulator path
        argv="${argv#* }" # drop target binary path
    fi
    while [[ "${argv}" == *" " ]]; do argv="${argv% }"; done # NUL->space left a trailer
    printf '%s' "${argv}"
}

# Verify the entrypoint forwards server arguments to asd. This is a documented
# interface (README: "Passing server command-line arguments") that container
# orchestrators rely on to set server flags without replacing the entrypoint, so
# it needs coverage against future entrypoint changes.
function check_arg_passthrough() {
    local probe="${CONTAINER}-args"
    # Two properties make this probe able to fail:
    #
    # 1. The FIRST token must be one the entrypoint could never emit on its own,
    #    otherwise the test proves nothing. --config-file cannot lead: its value here
    #    is both asd's default and the exact path the entrypoint writes the conf to,
    #    so an entrypoint that dropped "$@" and hardcoded that flag would produce a
    #    byte-identical argv and pass. --early-verbose is inert (verbose logging
    #    before config parse), is never synthesized by the entrypoint, and exists in
    #    every shipped lineage.
    # 2. More than one token, because "$@" and "$1" are indistinguishable at argc 1.
    #    An entrypoint mutated to forward only its first argument would otherwise
    #    pass -- and multi-token is the case orchestrators actually depend on, since
    #    a flag with a value ("--preview yaml-config") is two argv tokens. Three
    #    tokens also kills a "$1" "$2" mutation. --config-file is safe as a
    #    non-leading token precisely because token 1 can no longer be synthesized,
    #    and the entrypoint guarantees that path exists (it writes the conf there).
    local probe_args=(--early-verbose --config-file /etc/aerospike/aerospike.conf)
    # IFS is unmodified, so [*] joins with a single space -- matching the argv
    # rendering the /proc scan below produces.
    local expect="asd ${probe_args[*]} --fgdaemon"

    log_info "Verifying server argument passthrough..."

    docker rm -f "${probe}" >/dev/null 2>&1 || true

    local run_opts=(-td --name "${probe}" -e "DEFAULT_TTL=30d")
    [ -n "${PLATFORM}" ] && run_opts+=("--platform=${PLATFORM}")

    if ! docker run "${run_opts[@]}" "${IMAGE_TAG}" "${probe_args[@]}" >/dev/null 2>&1; then
        log_failure "Container failed to start when given server arguments"
        docker logs "${probe}" 2>&1 | tail -20 || true
        docker rm -f "${probe}" >/dev/null 2>&1 || true
        exit 1
    fi

    local argv=""
    if ! argv=$(asd_argv "${probe}"); then
        # Most likely cause is asd rejecting the forwarded flag, so show the logs
        # before the container goes away.
        log_failure "Could not locate asd process in container"
        docker logs "${probe}" 2>&1 | tail -20 || true
        docker rm -f "${probe}" >/dev/null 2>&1 || true
        exit 1
    fi

    docker rm -f "${probe}" >/dev/null 2>&1 || true

    # Compare the whole argv, not substrings. An exact match is what proves the
    # entrypoint prepended asd, forwarded our flag, and appended --fgdaemon -- and
    # it also catches arguments being injected, dropped, or reordered.
    if [ "${argv}" != "${expect}" ]; then
        log_failure "Unexpected asd argv"
        log_failure "  expected: ${expect}"
        # Report the string that was actually compared, not the raw cmdline. Under
        # emulation the raw form additionally differs by the two stripped prefix
        # tokens, which would obscure the real mismatch.
        log_failure "  actual:   ${argv}"
        exit 1
    fi

    log_success "Server arguments forwarded to asd"
}

# The entrypoint execs a first argument that is neither an option nor "asd" as the
# container command (README documents `bash` giving a shell). check_arg_passthrough
# covers the option branch and the default CMD ["asd"] covers the asd branch, so
# without this the command branch is the one documented behavior with no coverage.
function check_command_passthrough() {
    log_info "Verifying non-option command passthrough..."

    local run_opts=(--rm)
    [ -n "${PLATFORM}" ] && run_opts+=("--platform=${PLATFORM}")

    local out=""
    out=$(docker run "${run_opts[@]}" "${IMAGE_TAG}" bash -c 'echo command-passthrough-ok' 2>/dev/null) || true

    if [[ "${out}" != *command-passthrough-ok* ]]; then
        log_failure "Entrypoint did not exec a non-option command as given: ${out:-<no output>}"
        exit 1
    fi

    log_success "Non-option command exec'd as given"
}

# A custom --config-file gets the FEATURE_KEY_FILE the user set added on
# Enterprise and Federal (README: "Advanced Configuration"), through a copy the
# image owns, since the mounted file is often read-only. Every other case must
# leave the server argv exactly as given. Configs are mounted read-only and
# compared with their originals afterwards.
FK_DIR=""
FK_KEY=""
FK_CONF_DIR=/opt/aerospike/etc
FK_COPY=/var/run/aerospike/aerospike.conf

function _fk_write_configs() {
    cat >"${FK_DIR}/no-service.conf" <<'EOF'
logging {
	console {
		context any info
	}
}

network {
	service {
		address any
		port 3000
	}
	heartbeat {
		mode mesh
		address local
		port 3002
	}
	fabric {
		address local
		port 3001
	}
}

namespace test {
	replication-factor 1
	storage-engine device {
		file /opt/aerospike/data/test.dat
		filesize 1G
	}
}
EOF
    {
        printf 'service {\n\tcluster-name custom\n}\n\n'
        cat "${FK_DIR}/no-service.conf"
    } >"${FK_DIR}/custom.conf"
    {
        printf 'service {\n\tfeature-key-file %s/features.conf\n\tcluster-name custom\n}\n\n' "${FK_CONF_DIR}"
        cat "${FK_DIR}/no-service.conf"
    } >"${FK_DIR}/has-key.conf"

    local f
    for f in no-service custom has-key; do
        cp "${FK_DIR}/${f}.conf" "${FK_DIR}/${f}.conf.orig"
    done
}

# _fk_case NAME CONFIG EXPECTED_ARGV KEY_SOURCE [docker run options] -- [server args]
# CONFIG is mounted read-only at ${FK_CONF_DIR}/aerospike.conf ("" mounts none).
# KEY_SOURCE, when set, must appear in asd's "loaded feature key" log line. Log
# lines about the feature key are never printed.
function _fk_case() {
    local name=$1 config=$2 expect=$3 key_source=$4
    shift 4
    local -a opts=()
    while [ "$1" != -- ]; do
        opts+=("$1")
        shift
    done
    shift

    local probe="${CONTAINER}-fk"
    docker rm -f "${probe}" >/dev/null 2>&1 || true

    local run_opts=(-d --name "${probe}" -e "DEFAULT_TTL=30d")
    [ -n "${PLATFORM}" ] && run_opts+=("--platform=${PLATFORM}")
    [ -n "${config}" ] && run_opts+=(-v "${FK_DIR}/${config}:${FK_CONF_DIR}/aerospike.conf:ro")
    run_opts+=(-v "${FK_KEY}:${FK_CONF_DIR}/features.conf:ro")

    if ! docker run "${run_opts[@]}" "${opts[@]}" "${IMAGE_TAG}" "$@" >/dev/null 2>&1; then
        log_failure "Custom config, ${name}: container failed to start"
        exit 1
    fi

    local argv=""
    if ! argv=$(asd_argv "${probe}"); then
        log_failure "Custom config, ${name}: could not locate asd process in container"
        docker logs "${probe}" 2>&1 | grep -iv feature | tail -20 || true
        exit 1
    fi

    if [ "${argv}" != "${expect}" ]; then
        log_failure "Custom config, ${name}: unexpected asd argv"
        log_failure "  expected: ${expect}"
        log_failure "  actual:   ${argv}"
        exit 1
    fi

    local attempt attempts serving=false
    attempts=$(asd_wait_attempts)
    for ((attempt = 0; attempt < attempts; attempt++)); do
        if [[ "$(docker exec "${probe}" asinfo -v status 2>/dev/null)" == ok* ]]; then
            serving=true
            break
        fi
        sleep 1
    done
    if [ "${serving}" != true ]; then
        log_failure "Custom config, ${name}: asd is not serving"
        docker logs "${probe}" 2>&1 | grep -iv feature | tail -20 || true
        exit 1
    fi

    if [ -n "${key_source}" ]; then
        local loaded=false logs line
        for ((attempt = 0; attempt < attempts; attempt++)); do
            logs=$(docker logs "${probe}" 2>&1) || true
            while IFS= read -r line; do
                [[ "${line}" == *"loaded feature key "*" (${key_source})" ]] && loaded=true
            done <<<"${logs}"
            [ "${loaded}" = true ] && break
            sleep 1
        done
        if [ "${loaded}" != true ]; then
            log_failure "Custom config, ${name}: asd did not load the feature key from ${key_source}"
            docker logs "${probe}" 2>&1 | grep -iv feature | tail -20 || true
            exit 1
        fi
    fi

    docker rm -f "${probe}" >/dev/null 2>&1 || true

    if [ -n "${config}" ] && ! cmp -s "${FK_DIR}/${config}" "${FK_DIR}/${config}.orig"; then
        log_failure "Custom config, ${name}: mounted config was modified"
        exit 1
    fi

    log_success "Custom config, ${name}"
}

# _fk_run_to_exit CONFIG [docker run options] -- [server args]
# Runs a case whose asd is expected to exit, and waits until it has.
function _fk_run_to_exit() {
    local config=$1
    shift
    local -a opts=()
    while [ "$1" != -- ]; do
        opts+=("$1")
        shift
    done
    shift

    local probe="${CONTAINER}-fk"
    docker rm -f "${probe}" >/dev/null 2>&1 || true

    local run_opts=(-d --name "${probe}")
    [ -n "${PLATFORM}" ] && run_opts+=("--platform=${PLATFORM}")
    [ -n "${config}" ] && run_opts+=(-v "${FK_DIR}/${config}:${FK_CONF_DIR}/aerospike.conf:ro")
    docker run "${run_opts[@]}" "${opts[@]}" "${IMAGE_TAG}" "$@" >/dev/null 2>&1 || true

    local attempt attempts
    attempts=$(asd_wait_attempts)
    for ((attempt = 0; attempt < attempts; attempt++)); do
        [ "$(docker container inspect -f '{{.State.Running}}' "${probe}" 2>/dev/null)" = false ] && return 0
        sleep 1
    done
    return 0
}

function check_feature_key_custom_config() {
    log_info "Verifying FEATURE_KEY_FILE with a custom configuration file..."

    local once_opts=(--rm)
    [ -n "${PLATFORM}" ] && once_opts+=("--platform=${PLATFORM}")
    local enterprise=true
    if [[ "$(docker run "${once_opts[@]}" --entrypoint asd "${IMAGE_TAG}" --version 2>/dev/null)" == *Community* ]]; then
        enterprise=false
    fi

    FK_DIR=$(mktemp -d)
    # Resolved so a Docker VM that shares the host's real paths (macOS) can mount it.
    FK_DIR=$(cd "${FK_DIR}" && pwd -P)
    _fk_write_configs

    # The key mounted for the cases: FEATURES_CONF_PATH, or else a copy of the
    # image's own default key, which also tells whether asd has a default key
    # to fall back on when FEATURE_KEY_FILE is unset.
    local image_key=false
    touch "${FK_DIR}/features.conf"
    if [ "${enterprise}" = true ] &&
        docker run "${once_opts[@]}" --entrypoint cat "${IMAGE_TAG}" /etc/aerospike/features.conf \
            >"${FK_DIR}/features.conf" 2>/dev/null && [ -s "${FK_DIR}/features.conf" ]; then
        image_key=true
    fi
    FK_KEY="${FEATURES_CONF_PATH:-${FK_DIR}/features.conf}"

    local key="${FK_CONF_DIR}/features.conf" conf="${FK_CONF_DIR}/aerospike.conf"
    local loaded="" default_loaded="" new_conf="${conf}"
    if [ "${enterprise}" = true ]; then
        new_conf="${FK_COPY}"
        if [ -s "${FK_KEY}" ]; then
            loaded="${key}"
        else
            log_warn "No feature key available (set FEATURES_CONF_PATH); not checking which key asd loads"
        fi
        [ "${image_key}" = true ] && default_loaded=/etc/aerospike/features.conf
    fi

    _fk_case "directive added, read-only config unchanged" custom.conf \
        "asd --config-file ${new_conf} --fgdaemon" "${loaded}" \
        -e "FEATURE_KEY_FILE=${key}" -- --config-file "${conf}"

    _fk_case "--config-file= form" custom.conf \
        "asd --config-file=${new_conf} --fgdaemon" "${loaded}" \
        -e "FEATURE_KEY_FILE=${key}" -- "--config-file=${conf}"

    # asd will not start without a service context (cluster-name belongs there),
    # so the copy is read back from the exited container instead.
    local probe="${CONTAINER}-fk"
    _fk_run_to_exit no-service.conf -e "FEATURE_KEY_FILE=${key}" -- --config-file "${conf}"
    rm -f "${FK_DIR}/copy.conf"
    docker cp "${probe}:${FK_COPY}" "${FK_DIR}/copy.conf" >/dev/null 2>&1 || true
    docker rm -f "${probe}" >/dev/null 2>&1 || true
    if [ "${enterprise}" = true ]; then
        {
            cat "${FK_DIR}/no-service.conf"
            printf '\nservice {\n\tfeature-key-file %s\n}\n' "${key}"
        } >"${FK_DIR}/copy.expected"
        if ! cmp -s "${FK_DIR}/copy.conf" "${FK_DIR}/copy.expected"; then
            log_failure "Custom config, no service context: ${FK_COPY} lacks the appended service context"
            exit 1
        fi
    elif [ -e "${FK_DIR}/copy.conf" ]; then
        log_failure "Custom config, no service context: ${FK_COPY} written on Community"
        exit 1
    fi
    if ! cmp -s "${FK_DIR}/no-service.conf" "${FK_DIR}/no-service.conf.orig"; then
        log_failure "Custom config, no service context: mounted config was modified"
        exit 1
    fi
    log_success "Custom config, no service context"

    local schema=/opt/aerospike/schema/aerospike_config_schema.json
    _fk_case "other arguments unchanged and in order" custom.conf \
        "asd --early-verbose --config-file ${new_conf} --schema-file ${schema} --fgdaemon" "${loaded}" \
        -e "FEATURE_KEY_FILE=${key}" -- --early-verbose --config-file "${conf}" --schema-file "${schema}"

    local -x FK_FEATURES_B64=""
    FK_FEATURES_B64=$(base64 <"${FK_KEY}" | tr -d '\n')
    local b64_loaded=""
    [ -n "${loaded}" ] && b64_loaded="env-b64:FK_FEATURES_B64"
    _fk_case "FEATURE_KEY_FILE=env-b64:" custom.conf \
        "asd --config-file ${new_conf} --fgdaemon" "${b64_loaded}" \
        -e FK_FEATURES_B64 -e "FEATURE_KEY_FILE=env-b64:FK_FEATURES_B64" -- --config-file "${conf}"

    if [ "${enterprise}" = true ]; then
        _fk_case "existing feature-key-file kept" has-key.conf \
            "asd --config-file ${conf} --fgdaemon" "${loaded}" \
            -e "FEATURE_KEY_FILE=${FK_CONF_DIR}/other-features.conf" -- --config-file "${conf}"
    else
        # Community rejects the directive, so asd exits naming it, and the
        # entrypoint must not have made a copy.
        _fk_run_to_exit has-key.conf -e "FEATURE_KEY_FILE=${FK_CONF_DIR}/other-features.conf" -- --config-file "${conf}"
        local logs=""
        logs=$(docker logs "${probe}" 2>&1) || true
        rm -f "${FK_DIR}/copy.conf"
        docker cp "${probe}:${FK_COPY}" "${FK_DIR}/copy.conf" >/dev/null 2>&1 || true
        docker rm -f "${probe}" >/dev/null 2>&1 || true
        if [[ "${logs}" != *"'feature-key-file' is enterprise-only"* ]] || [ -e "${FK_DIR}/copy.conf" ] ||
            ! cmp -s "${FK_DIR}/has-key.conf" "${FK_DIR}/has-key.conf.orig"; then
            log_failure "Custom config, existing feature-key-file kept: config not passed to asd unchanged"
            exit 1
        fi
        log_success "Custom config, existing feature-key-file kept"
    fi

    _fk_case "FEATURE_KEY_FILE unset" custom.conf \
        "asd --config-file ${conf} --fgdaemon" "${default_loaded}" \
        -- --config-file "${conf}"

    _fk_case "default template" "" \
        "asd --config-file /etc/aerospike/aerospike.conf --fgdaemon" "${default_loaded}" \
        -e "FEATURE_KEY_FILE=/etc/aerospike/features.conf" -- --config-file /etc/aerospike/aerospike.conf

    # A missing config is left to asd, which names the path it was given.
    local missing="${FK_CONF_DIR}/missing.conf"
    _fk_run_to_exit "" -e "FEATURE_KEY_FILE=${key}" -- --config-file "${missing}"
    local logs=""
    logs=$(docker logs "${probe}" 2>&1) || true
    docker rm -f "${probe}" >/dev/null 2>&1 || true
    if [[ "${logs}" != *"couldn't open configuration file ${missing}"* ]]; then
        log_failure "Custom config, missing config path: asd did not report ${missing}"
        exit 1
    fi
    log_success "Custom config, missing config path left to asd"

    rm -rf "${FK_DIR}"
    FK_DIR=""
}

# Optional first arg: "full" = also remove image when CLEAN=true (use after test).
# No arg = container only (use before run_docker so we don't remove the image we're about to run).
function cleanup() {
    docker stop "${CONTAINER}" 2>/dev/null || true
    docker rm -f "${CONTAINER}" 2>/dev/null || true
    # check_arg_passthrough's probe container, so an interrupt cannot leak a server.
    docker rm -f "${CONTAINER}-args" 2>/dev/null || true
    docker rm -f "${CONTAINER}-fk" 2>/dev/null || true
    [ -n "${FK_DIR}" ] && rm -rf "${FK_DIR}"
    if [ "${1:-}" = "full" ] && [ "${CLEAN}" = "true" ]; then
        docker rmi -f "${IMAGE_TAG}" 2>/dev/null || true
    fi
}

function run_snyk_scan() {
    local image=$1 arch=$2 dockerfile=${3:-}
    local edition=${4:-} version=${5:-} distro=${6:-}
    if [ "${SNYK_SCAN}" != "true" ]; then
        return 0
    fi
    if ! command -v snyk >/dev/null 2>&1; then
        log_warn "Snyk not found in PATH, skipping container scan"
        return 0
    fi
    local ts
    ts=$(date -u +%Y%m%d%H%M%S 2>/dev/null || date +%Y%m%d%H%M%S)
    local name="aerospike-server"
    [ -n "${edition}" ] && [ "${edition}" != "community" ] && name+="-${edition}"
    [ -n "${version}" ] && name+="-${version}"
    [ -n "${distro}" ] && name+="-${distro}"
    local scan_log="${name}-${arch}-${ts}.snyk"
    local snyk_cmd=(snyk container test "${image}" "--platform=linux/${arch}")
    [ -n "${dockerfile}" ] && [ -f "${dockerfile}" ] && snyk_cmd+=("--file=${dockerfile}")
    log_info "Running Snyk container scan..."
    # Snyk exit code is intentionally non-fatal (|| true): scan is informational,
    # not a build gate. A green test.sh run means functional tests passed; check
    # .snyk log files for vulnerability findings.
    "${snyk_cmd[@]}" | tee "${scan_log}" || true
    _snyk_summary "${scan_log}" "${image}"
}

function _snyk_summary() {
    local scan_log=$1 image=$2
    [ -f "${scan_log}" ] || return 0
    local critical=0 high=0
    critical=$(grep -c 'Critical severity vulnerability found in' "${scan_log}" || true)
    high=$(grep -c 'High severity vulnerability found in' "${scan_log}" || true)
    critical=${critical:-0}
    high=${high:-0}
    local CLR_CRITICAL="\e[91m" CLR_HIGH="\e[33m" CLR_RESET="\e[0m"
    if [ "${LOG_COLOR:-true}" = "false" ]; then
        CLR_CRITICAL="" CLR_HIGH="" CLR_RESET=""
    fi
    echo ""
    echo -e "  Snyk scan results for ${image}:"
    echo -e "    ${CLR_CRITICAL}Critical: ${critical}${CLR_RESET}"
    echo -e "    ${CLR_HIGH}High:     ${high}${CLR_RESET}"
    echo -e "    Log:      ${scan_log}"
    echo ""
}

function test_specific_image() {
    IMAGE_TAG="${SPECIFIC_IMAGE}"
    CONTAINER="aerospike-test-$$"

    local arch_display="${PLATFORM#*/}"
    [ -z "${arch_display}" ] && arch_display="(host)"
    log_info "====== Testing: ${IMAGE_TAG} ======"
    log_info "  Platform: ${PLATFORM}"
    log_info "  Architecture: ${arch_display}"
    [ -n "${EDITION}" ] && log_info "  Expected edition: ${EDITION}"
    echo ""

    local version
    version=$(echo "${IMAGE_TAG}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(-[a-z0-9-]+)?' || echo "")

    trap 'cleanup full' EXIT
    # Remove any previous container only
    cleanup
    run_docker
    check_container "${version}" "${EDITION}" "${arch_display}"
    check_arg_passthrough
    check_command_passthrough
    check_feature_key_custom_config
    run_snyk_scan "${IMAGE_TAG}" "${arch_display}" "" "${EDITION}" "${version}"
    cleanup full

    echo ""
    log_success "====== Test passed! ======"
}

function test_from_releases() {
    local lineage
    if [[ "${VERSION_OR_LINEAGE}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+ ]]; then
        lineage=$(get_lineage_from_version "${VERSION_OR_LINEAGE}")
    else
        lineage="${VERSION_OR_LINEAGE}"
    fi

    local arch_list=""
    for p in "${PLATFORMS_LIST[@]}"; do arch_list="${arch_list} ${p#*/}"; done
    arch_list=${arch_list# }
    log_info "Testing: ${lineage}"
    [ -n "${EDITION}" ] && log_info "  Edition: ${EDITION}"
    [ -n "${DISTRIBUTION}" ] && log_info "  Distro: ${DISTRIBUTION}"
    log_info "  Platform(s): ${PLATFORMS_LIST[*]}"
    log_info "  Architecture(s): ${arch_list}"
    echo ""

    local editions=${EDITION:-$(support_editions)}
    local distros
    distros=$(support_distros_matching "${lineage}" "${DISTRIBUTION:-}")
    local tested=0
    local skip_no_dir=0
    local skip_no_image=0

    # Report which release dirs exist (so user sees why only one may be tested)
    local existing_dirs=""
    for edition in ${editions}; do
        for distro in ${distros}; do
            [ -d "releases/${lineage}/${edition}/${distro}" ] && existing_dirs="${existing_dirs} ${edition}/${distro}"
        done
    done
    existing_dirs=${existing_dirs# }
    log_info "Release dirs for ${lineage}: ${existing_dirs:-none}"
    echo ""

    for edition in ${editions}; do
        for distro in ${distros}; do
            local dir="releases/${lineage}/${edition}/${distro}"
            if [ ! -d "${dir}" ]; then
                skip_no_dir=$((skip_no_dir + 1))
                log_info "Skipping ${edition}/${distro}: no releases/ directory"
                continue
            fi

            local version
            version=$(get_version_from_dockerfile "${lineage}" "${edition}" "${distro}") || continue
            version=$(printf '%s' "${version}" | tr -d '\r\n\t ')
            [ -z "${version}" ] && continue

            for plat in "${PLATFORMS_LIST[@]}"; do
                local arch=${plat#*/}
                # Federal only supports amd64
                if [ "${edition}" = "federal" ] && [ "${arch}" = "arm64" ]; then
                    continue
                fi

                IMAGE_TAG=$(get_image_tag_from_bake "${lineage}" "${edition}" "${distro}" "${arch}") || true
                if [ -z "${IMAGE_TAG}" ]; then
                    local img_base="aerospike/aerospike-server"
                    [ "${edition}" != "community" ] && img_base+="-${edition}"
                    # Match docker-build.sh: single-distro build uses version-arch, multi uses version-distro-arch
                    IMAGE_TAG="${img_base}:${version}-${distro}-${arch}"
                    if ! docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
                        IMAGE_TAG="${img_base}:${version}-${arch}"
                    fi
                fi

                CONTAINER="aerospike-test-${edition}-${distro//./}-${arch}-$$"

                log_info "====== Testing: ${IMAGE_TAG} (${plat}) ======"

                if ! docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
                    skip_no_image=$((skip_no_image + 1))
                    log_warn "Skipping ${edition}/${distro}/${arch}: image not found locally"
                    continue
                fi

                PLATFORM="${plat}"
                trap 'cleanup full' EXIT
                # Remove any previous container only
                cleanup
                run_docker
                check_container "${version}" "${edition}" "${arch}" \
                    "releases/${lineage}/${edition}/${distro}/Dockerfile"
                check_arg_passthrough
                check_command_passthrough
                check_feature_key_custom_config
                run_snyk_scan "${IMAGE_TAG}" "${arch}" "releases/${lineage}/${edition}/${distro}/Dockerfile" "${edition}" "${version}" "${distro}"
                cleanup full

                tested=$((tested + 1))
                echo ""
            done
        done
    done

    if [ "${tested}" -eq 0 ]; then
        log_warn "No images found. Run docker-build.sh first."
        exit 1
    fi
    log_info "Summary: ${tested} tested, ${skip_no_dir} skipped (no releases/ dir), ${skip_no_image} skipped (image not built)"
    log_success "====== All ${tested} test(s) passed! ======"
}

function main() {
    parse_args "$@"
    if [ -n "${SPECIFIC_IMAGE}" ]; then
        test_specific_image
    else
        test_from_releases
    fi
}

main "$@"
