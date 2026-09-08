#!/usr/bin/env bash
# HTTP fetch helper. Used by lib/version.sh; callers must source lib/log.sh for log_debug.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.

set -Eeuo pipefail

# Applied to every host-side curl. Without them a firewall that drops packets
# rather than refusing them hangs the whole run indefinitely: curl's default is
# no total timeout at all, and a full -g makes one listing per package directory.
AS_CURL_TIMEOUTS=(--connect-timeout 10 --max-time 60)

function fetch() {
    local tag=$1
    local link=$2

    log_debug "${tag} - ${link}"
    curl -fsSL "${AS_CURL_TIMEOUTS[@]}" "${link}" "${@:3}"
}
