#!/bin/bash

if [[ $# = 0 ]]; then
    VERSION="$(grep "ENV AEROSPIKE_VERSION" ./Dockerfile | cut -d' ' -f 3)"
else
    VERSION=$1
fi

docker build -t aerospike/aerospike-server-community:$VERSION .
