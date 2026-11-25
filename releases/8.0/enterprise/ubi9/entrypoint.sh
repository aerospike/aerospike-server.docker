#!/usr/bin/env bash

set -Eeuo pipefail

USER_FEATURE_KEY_FILE=${FEATURE_KEY_FILE:-}
export FEATURE_KEY_FILE=${FEATURE_KEY_FILE:-"/etc/aerospike/features.conf"}
export LOGFILE=${LOGFILE:-""}
export SERVICE_ADDRESS=${SERVICE_ADDRESS:-any}
export SERVICE_PORT=${SERVICE_PORT:-3000}
export NAMESPACE=${NAMESPACE:-test}
export DATA_IN_MEMORY=${DATA_IN_MEMORY:-false}
export DEFAULT_TTL=${DEFAULT_TTL:-0}
export MEM_GB=${MEM_GB:-1}
export NSUP_PERIOD=${NSUP_PERIOD:-120}
export STORAGE_GB=${STORAGE_GB:-4}

if [ "${DATA_IN_MEMORY}" = "true" ]; then
    export READ_PAGE_CACHE="false"
else
    export READ_PAGE_CACHE="true"
fi

if asd --version | grep -q "Community"; then
    FEATURE_KEY_FILE="" # invalid for community edition
    USER_FEATURE_KEY_FILE=""
fi

function bash_eval_template() {
    local template_file=$1
    local target_file=$2

    echo "" >"${target_file}"

    while IFS= read -r line; do
        if grep -qE "[$][(]|[{]" <<<"${line}"; then
            local update
            update=$(eval echo "\"${line}\"") || exit 1
            grep -qE "[^[:space:]]*" <<<"${update}" && echo "${update}" >>"${target_file}"
        else
            echo "${line}" >>"${target_file}"
        fi
    done <"${template_file}"

    # Ignore failure when template is mounted in a read-only filesystem.
    rm "${template_file}" || true
}

# Print the config in $1 with "feature-key-file $2" added to its first top-level
# service context, or with a service context appended when there is none.
function add_feature_key_file() {
    local config=$1 key_file=$2
    local line code tmp depth=0 added=false

    while IFS= read -r line || [ -n "${line}" ]; do
        echo "${line}"
        code=${line%%#*}
        if [ "${added}" = false ] && [ "${depth}" -eq 0 ] &&
            [[ "${code}" =~ ^[[:space:]]*service[[:space:]]*\{[[:space:]]*$ ]]; then
            echo "	feature-key-file ${key_file}"
            added=true
        fi
        tmp=${code//[^\{]/}
        depth=$((depth + ${#tmp}))
        tmp=${code//[^\}]/}
        depth=$((depth - ${#tmp}))
    done <"${config}"

    if [ "${added}" = false ]; then
        printf '\nservice {\n\tfeature-key-file %s\n}\n' "${key_file}"
    fi
}

# With a custom --config-file, add the FEATURE_KEY_FILE the user set to a copy of
# that config, unless it already names a feature key file, and point asd at the
# copy. The user's file is never written to.
function use_feature_key_file() {
    local -a args=("$@")
    local i config="" config_idx="" config_form=""

    for i in "${!args[@]}"; do
        case "${args[i]}" in
        --config-file)
            if [ $((i + 1)) -lt ${#args[@]} ]; then
                config_idx=$((i + 1))
                config=${args[config_idx]}
                config_form=separate
            fi
            ;;
        --config-file=*)
            config_idx=${i}
            config=${args[i]#--config-file=}
            config_form=joined
            ;;
        *yaml-config*)
            # Not the classic config format this edits.
            return 0
            ;;
        esac
    done

    [ -n "${config}" ] || return 0
    [ -f "${config}" ] && [ -r "${config}" ] || return 0
    grep -qE '^([^#]*[[:space:]{])?feature-key-file([[:space:]]|$)' "${config}" && return 0

    local copy=/var/run/aerospike/aerospike.conf
    mkdir -p "${copy%/*}"
    add_feature_key_file "${config}" "${USER_FEATURE_KEY_FILE}" >"${copy}"

    if [ "${config_form}" = joined ]; then
        args[config_idx]="--config-file=${copy}"
    else
        args[config_idx]=${copy}
    fi
    ASD_ARGS=("${args[@]}")
}

# Fill out conffile with above values
if [ -f /etc/aerospike/aerospike.template.conf ]; then
    conf=/etc/aerospike/aerospike.conf
    template=/etc/aerospike/aerospike.template.conf

    bash_eval_template "${template}" "${conf}"
fi

# Forwarding server arguments to asd is a documented interface (see README,
# "Passing server command-line arguments"). Container orchestrators rely on it to
# set server flags without replacing the entrypoint; preserve it.

# if command starts with an option, prepend asd
if [ "${1:0:1}" = '-' ]; then
    set -- asd "$@"
fi

# if asd is specified for the command, start it with any given options
if [ "$1" = 'asd' ]; then
    NETLINK=${NETLINK:-eth0}

    # We will wait a bit for the network link to be up.
    NETLINK_UP=0
    NETLINK_COUNT=0

    echo "link ${NETLINK} state $(cat /sys/class/net/"${NETLINK}"/operstate)"

    while [ ${NETLINK_UP} -eq 0 ] && [ ${NETLINK_COUNT} -lt 20 ]; do
        if grep -q "up" /sys/class/net/"${NETLINK}"/operstate; then
            NETLINK_UP=1
        else
            sleep 0.1
            ((++NETLINK_COUNT))
        fi
    done

    echo "link ${NETLINK} state $(cat /sys/class/net/"${NETLINK}"/operstate) in ${NETLINK_COUNT}"

    if [ -n "${USER_FEATURE_KEY_FILE}" ]; then
        ASD_ARGS=("$@")
        use_feature_key_file "$@"
        set -- "${ASD_ARGS[@]}"
    fi

    # asd should always run in the foreground.
    set -- "$@" --fgdaemon
fi

exec "$@"
