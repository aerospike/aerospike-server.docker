# shellcheck shell=bash

function array_empty() {
    local array=("$@")

    [ "${#array[@]}" -eq 0 ]
}

function in_array() {
    local needle=$1
    shift
    local array=("$@")

    printf '%s\0' "${array[@]}" | grep -Fxqz "${needle}";
}
