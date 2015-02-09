#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

url='git://github.com/aerospike/aerospike-server.docker'

echo '# maintainer: Lucien Volmar <lucien@aerospike.com> (@volmarl)'

commit="$(git log -1 --format='format:%H' -- .)"
fullVersion="$(grep -m1 'ENV AEROSPIKE_VERSION ' Dockerfile | cut -d' ' -f3)"

versionAliases=()
# uncomment if you want aliases like: 3, 3.4 for 3.4.1
#while [ "${fullVersion%.*}" != "$fullVersion" ]; do
#	versionAliases+=( $fullVersion )
#	fullVersion="${fullVersion%.*}"
#done
versionAliases+=( $fullVersion latest )

echo
for va in "${versionAliases[@]}"; do
	echo "$va: ${url}@${commit}"
done
