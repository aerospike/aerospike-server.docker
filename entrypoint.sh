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

fi

# the command isn't asd so run the command the user specified

exec "$@"
