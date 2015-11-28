#!/bin/bash
set -e

# if command starts with an option, prepend asd
if [ "${1:0:1}" = '-' ]; then
	set -- asd "$@"
fi

# if asd is specified for the command, start it with any given options
if [ "$1" = 'asd' ]; then
	# asd should always run in the foreground
	set -- "$@" --foreground

	# check data volume ownership
	if [ ! -O /opt/aerospike/data ]; then
		echo 'ERROR: /opt/aerospike/data is not owned by the aerospike user'
		echo 'This should only happen with a volume mounted at /opt/aerospike/data'
		echo
		echo "To fix, use the following docker run command and"
		echo "replace IMAGEID and VOLUME_BIND with the proper values:"
		echo "docker run -u root -v VOLUME_BIND IMAGEID chown -R 24183:24183 /opt/aerospike"

		exit 1
	fi
fi

# the command isn't asd so run the command the user specified
exec "$@"
