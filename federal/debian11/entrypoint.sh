#!/usr/bin/env bash

set -Eeuo pipefail

export FEATURE_KEY_FILE=${FEATURE_KEY_FILE:-"/etc/aerospike/features.conf"}
export LOGFILE=${LOGFILE:-""}
export SERVICE_ADDRESS=${SERVICE_ADDRESS:-any}
export SERVICE_PORT=${SERVICE_PORT:-3000}
export NAMESPACE=${NAMESPACE:-test}
export DATA_IN_MEMORY=${DATA_IN_MEMORY:-false}
export DEFAULT_TTL=${DEFAULT_TTL:-30d}
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
fi

function bash_eval_template() {
	local template_file=$1
	local target_file=$2

	local template=
	template=$(cat "${template_file}")
	local expanded=
	expanded=$(eval echo "\"${template}\"" | grep -Ev '^[[:blank:]]*$')

	# Ignore failure when template is mounted in a read-only filesystem.
	rm "${template_file}" || true
	echo "${expanded}" >"${target_file}"
}

# Fill out conffile with above values
if [ -f /etc/aerospike/aerospike.template.conf ]; then
	conf=/etc/aerospike/aerospike.conf
	template=/etc/aerospike/aerospike.template.conf

	bash_eval_template "${template}" "${conf}"
fi

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
	# asd should always run in the foreground.
	set -- "$@" --foreground
fi

exec "$@"
