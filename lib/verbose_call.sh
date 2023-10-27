#!/usr/bin/env bash

set -Eeuo pipefail

function verbose_call() {
    set -x

    eval "${*}"
    rv=$?

    set +x

    return $rv
}
