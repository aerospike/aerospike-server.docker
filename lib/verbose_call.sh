# shellcheck shell=bash

function verbose_call() {
    set -x

    eval "${*}"
    rv=$?

    set +x

    return $rv
}
