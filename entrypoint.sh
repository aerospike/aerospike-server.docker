#!/bin/bash
set -e


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
