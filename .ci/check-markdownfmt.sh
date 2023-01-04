#!/usr/bin/env bash
set -Eeuo pipefail

files="$(
	find \( \
		-name '*.md' \
		\) -exec test -s '{}' ';' -print0 |
		xargs -0 .ci/markdownfmt.sh -l
)"

if [ "$files" ]; then
	echo >&2 'Need markdownfmt:'
	echo >&2 "$files"
	echo >&2
	echo "$files" | xargs .ci/markdownfmt.sh -d >&2
	exit 1
fi
