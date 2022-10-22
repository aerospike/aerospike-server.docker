#!/usr/bin/env bash

set -e

edition="$(grep "ARG AEROSPIKE_EDITION" ./Dockerfile | cut -d = -f 2)"

if [[ $# = 0 ]]; then
    version="$(grep "ARG AEROSPIKE_VERSION" ./Dockerfile | cut -d = -f 2)"
else
    version=$1
fi

docker build --progress plain -t "aerospike/aerospike-server-${edition}:${version}" .
