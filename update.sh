#!/usr/bin/env bash
set -e

edition=$(grep "ARG AEROSPIKE_EDITION" ./Dockerfile | cut -d = -f 2)
fullVersion=$(curl -sSL "https://artifacts.aerospike.com/aerospike-server-${edition}/" | grep -E '<a href="[0-9.-]+[-]*.*/"' | sed -r 's!.*<a href="([0-9.-]+[-]*.*)/".*!\1!' | sort -V | tail -1)
sha256=$(curl -sSL "https://artifacts.aerospike.com/aerospike-server-${edition}/${fullVersion}/aerospike-server-${edition}-${fullVersion}-debian11.tgz.sha256" | cut -d' ' -f1)

set -x
sed -ri '
	s/^(ARG AEROSPIKE_VERSION) .*/\1='"${fullVersion}"'/;
	s/^(ARG AEROSPIKE_SHA256) .*/\1='"${sha256}"'/;
' Dockerfile
