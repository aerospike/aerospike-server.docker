#!/usr/bin/env bash

set -Eeuo pipefail

function fetch() {
    local tag=$1
    local link=$2

    log_debug "${tag} - ${link}"
    curl -fsSL "${link}" "${@:3}"
}
