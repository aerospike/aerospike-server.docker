#!/bin/bash
set -e

export CORES=$(grep -c ^processor /proc/cpuinfo)
export SERVICE_THREADS=${SERVICE_THREADS:-$CORES}
export TRANSACTION_QUEUES=${TRANSACTION_QUEUES:-$CORES}
export TRANSACTION_THREADS_PER_QUEUE=${TRANSACTION_THREADS_PER_QUEUE:-4}
export LOGFILE=${LOGFILE:-/dev/null}
export SERVICE_ADDRESS=${SERVICE_ADDRESS:-any}
export SERVICE_PORT=${SERVICE_PORT:-3000}
export HB_ADDRESS=${HB_ADDRESS:-any}
export HB_PORT=${HB_PORT:-3002}
export FABRIC_ADDRESS=${FABRIC_ADDRESS:-any}
export FABRIC_PORT=${FABRIC_PORT:-3001}
export INFO_ADDRESS=${INFO_ADDRESS:-any}
export INFO_PORT=${INFO_PORT:-3003}
export NAMESPACE=${NAMESPACE:-test}
export REPL_FACTOR=${REPL_FACTOR:-2}
export MEM_GB=${MEM_GB:-1}
export DEFAULT_TTL=${DEFAULT_TTL:-30d}
export STORAGE_GB=${STORAGE_GB:-4}

# Fill out conffile with above values
if [ -f /etc/aerospike/aerospike.template.conf ]; then
        envsubst < /etc/aerospike/aerospike.template.conf > /etc/aerospike/aerospike.conf
fi

# if command starts with an option, prepend asd
if [ "${1:0:1}" = '-' ]; then
	set -- asd "$@"
fi

# if asd is specified for the command, start it with any given options
if [ "$1" = 'asd' ]; then

	NETLINK=${NETLINK:-eth0}


	# we will wait a bit for the network link to be up.
	NETLINK_UP=0
	NETLINK_COUNT=0
	echo "link $NETLINK state $(cat /sys/class/net/${NETLINK}/operstate)"
	while [ $NETLINK_UP -eq 0 ] && [ $NETLINK_COUNT -lt 20 ]; do
		if grep -q "up" /sys/class/net/${NETLINK}/operstate; then
	                NETLINK_UP=1
	        else
	                sleep 0.1
                	let NETLINK_COUNT=NETLINK_COUNT+1
        	fi
	done
	echo "link $NETLINK state $(cat /sys/class/net/${NETLINK}/operstate) in ${NETLINK_COUNT}"

	# asd should always run in the foreground
	set -- "$@" --foreground

fi

# the command isn't asd so run the command the user specified

exec "$@"
