#!/usr/bin/env bash

set -e

# keep track of the last executed command
# shellcheck disable=SC2154
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG

# echo an error message before exiting
# shellcheck disable=SC2154
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT


log() {
    if [ "${DEBUG}" = "true" ]; then
        msg=$1
        echo "debug: $msg" "${@:2}" >&2
    fi
}

fetch() {
    tag=$1
    link=$2
    dest=$3

    log "${tag} - ${link}"
    curl -sSL "${link}" --output "${dest}" "${@:4}"
}

bootstrap() {
    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y
    apt-get install -y --no-install-recommends \
        apt-utils \
        2>&1 | grep -v "delaying package configuration"

    apt-get upgrade -y

    apt-get install -y --no-install-recommends \
        binutils \
        ca-certificates \
        curl \
        xz-utils

    install_tini
    install_config_template_dependencies
    install_aerospike_server_and_tools

    rm -rf aerospike-server.tgz /var/lib/apt/lists/*
    dpkg -r \
        apt-utils \
        binutils \
        ca-certificates \
        curl \
        xz-utils

    dpkg --purge \
        apt-utils \
        binutils \
        ca-certificates \
        curl \
        xz-utils 2>&1

    apt-get purge -y
    apt-get autoremove -y
}

install_tini() {
    fetch "tini" https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static /usr/bin/as-tini-static

    AS_TINI_SHA256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940
    echo "${AS_TINI_SHA256} /usr/bin/as-tini-static" | sha256sum -c -
    chmod +x /usr/bin/as-tini-static
}

install_config_template_dependencies() {
    apt-get install -y --no-install-recommends \
        gettext-base
}

install_aerospike_server() {
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ]; then
        apt-get install -y --no-install-recommends \
            libcurl4 \
            libldap-2.4.2
    fi

    dpkg -i aerospike/aerospike-server-*.deb
    rm -rf /opt/aerospike/bin
}

install_aerospike_tools_subset() {
    ar --output aerospike/pkg -x aerospike/aerospike-tools-*.deb
    tar xf aerospike/pkg/data.tar.xz -C aerospike/pkg/

    find aerospike/pkg/opt/aerospike/bin/ -user aerospike -group aerospike -exec chown root:root {} +
    mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike

    # Since tools release 7.0.5, asadm has been moved from /opt/aerospike/bin/asadm to /opt/aerospike/bin/asadm/asadm (inside an asadm directory)
    if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then
        mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/;
        ln -s /usr/lib/asadm/asadm /usr/bin/asadm;
        # Since tools release 7.1.1, asinfo has been moved from /opt/aerospike/bin/asinfo to /opt/aerospike/bin/asadm/asinfo (inside an asadm directory)
        if [ -f /usr/lib/asadm/asinfo ]; then
            ln -s /usr/lib/asadm/asinfo /usr/bin/asinfo;
        fi
    fi
}

install_aerospike_server_and_tools() {
    mkdir -p aerospike/pkg

    fetch "server/tools pkg" "https://artifacts.aerospike.com/aerospike-server-${AEROSPIKE_EDITION}/${AEROSPIKE_VERSION}/aerospike-server-${AEROSPIKE_EDITION}-${AEROSPIKE_VERSION}-debian11.tgz" aerospike-server.tgz
    echo "${AEROSPIKE_SHA256} aerospike-server.tgz" | sha256sum -c -
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike

    install_aerospike_server
    install_aerospike_tools_subset

    rm aerospike-server.tgz
    rm -rf aerospike
}

bootstrap
