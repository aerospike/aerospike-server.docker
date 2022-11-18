#!/usr/bin/env bash

set -Eeuo pipefail

function log_debug() {
	local msg=$1

	if [ "${DEBUG:=}" = "true" ]; then
		echo "debug: ${msg}" "${@:2}" >&2
	fi
}

function log_warn() {
	local msg=$1

	echo "warn: ${msg}" "${@:2}" >&2
}

function log_info() {
	local msg=$1

	echo "info: ${msg}" "${@:2}" >&2
}
