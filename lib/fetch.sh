#!/usr/bin/env bash
# HTTP fetch helper. Used by lib/version.sh; callers must source lib/log.sh for log_debug.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.

set -Eeuo pipefail

function fetch() {
    local tag=$1
    local link=$2

    log_debug "${tag} - ${link}"
    curl -fsSL "${link}" "${@:3}"
}
