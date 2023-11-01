LOG_RED="\e[31m"
LOG_GREEN="\e[32m"

LOG_ENDCOLOR="\e[0m"

if [ "${LOG_COLOR:="true"}" = "false" ]; then
    LOG_RED=
    LOG_GREEN=
    LOG_ENDCOLOR=
fi

function _log_level() {
    level=$1
    msg=$2

    echo -e "${level} ${BASH_SOURCE[2]}:${BASH_LINENO[1]} - ${msg}" >&2
}

function log_debug() {
    local msg=$1

    if [ "${DEBUG:=}" = "true" ]; then
        _log_level "debug" "${msg}"
    fi
}

function log_warn() {
    local msg=$1

    _log_level "warn" "${LOG_RED}${msg}${LOG_ENDCOLOR}"
}

function log_failure() {
    local msg=$1

    _log_level "fail" "${LOG_RED}${msg}${LOG_ENDCOLOR}"
}

function log_success() {
    local msg=$1

    _log_level "success" "${LOG_GREEN}${msg}${LOG_ENDCOLOR}"
}

function log_info() {
    local msg=$1

    _log_level "info" "${msg}"
}
