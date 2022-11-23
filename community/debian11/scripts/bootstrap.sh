#!/usr/bin/env bash

set -Eeuo pipefail

# keep track of the last executed command
# shellcheck disable=SC2154
trap 'last_command=${current_command:=""}; current_command=$BASH_COMMAND' DEBUG

# echo an error message before exiting
# shellcheck disable=SC2154
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

ARCH="$(uname -m)"

log_debug() {
	local msg=$1

	if [ "${DEBUG}" = "true" ]; then
		echo "debug: ${msg}" "${@:2}" >&2
	fi
}

log_warn() {
	local msg=$1

	echo "warn: ${msg}" "${@:2}" >&2
}

fetch() {
	local tag=$1
	local link=$2

	log_debug "${tag} - ${link}"
	curl -fsSL "${link}" "${@:3}"
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
	install_aerospike_server_and_tools

	# procps is needed for tests.
	apt-get install -y --no-install-recommends procps

	rm -rf /var/lib/apt/lists/*

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

	unset DEBIAN_FRONTEND
}

install_tini() {
	if [ "${ARCH}" = "x86_64" ]; then
		local sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940
		local suffix=""
	elif [ "${ARCH}" = "aarch64" ]; then
		local sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b
		local suffix="-arm64"
	else
		log_warn "Unsuported architecture - ${ARCH}"
		exit 1
	fi

	fetch "tini" "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" --output /usr/bin/as-tini-static

	echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -
	chmod +x /usr/bin/as-tini-static
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
	cd aerospike/pkg # ar on debian10 doesn't support '--output'
	ar -x ../aerospike-tools*.deb
	cd -
	tar xf aerospike/pkg/data.tar.xz -C aerospike/pkg/

	find aerospike/pkg/opt/aerospike/bin/ -user aerospike -group aerospike -exec chown root:root {} +
	mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike

	# Since tools release 7.0.5, asadm has been moved from /opt/aerospike/bin/asadm to /opt/aerospike/bin/asadm/asadm (inside an asadm directory)
	if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then
		mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/
		ln -s /usr/lib/asadm/asadm /usr/bin/asadm

		# Since tools release 7.1.1, asinfo has been moved from /opt/aerospike/bin/asinfo to /opt/aerospike/bin/asadm/asinfo (inside an asadm directory)
		if [ -f /usr/lib/asadm/asinfo ]; then
			ln -s /usr/lib/asadm/asinfo /usr/bin/asinfo
		fi
	fi
}

install_aerospike_server_and_tools() {
	local pkg_paths
	local sha256

	mkdir -p aerospike/pkg

	pkg_paths=("aerospike-server-${AEROSPIKE_EDITION}_${AEROSPIKE_VERSION}_tools-${AEROSPIKE_TOOLS_VERSION}_${LINUX_DISTRO}_${ARCH}.tgz")

	if [ "${ARCH}" = "x86_64" ]; then
		# Old format for pre-6.2
		pkg_paths+=("aerospike-server-${AEROSPIKE_EDITION}-${AEROSPIKE_VERSION}-${LINUX_DISTRO}.tgz")
		sha256="${AEROSPIKE_SHA_X86_64}"
	elif [ "${ARCH}" = "aarch64" ]; then
		sha256="${AEROSPIKE_SHA_AARCH64}"
	else
		log_warn "Unsuported architecture - ${ARCH}"
		exit 1
	fi

	local pkg_list_path="aerospike-server-${AEROSPIKE_EDITION}/${AEROSPIKE_VERSION}"
	local pkg_url
	local found=false

	for pkg_path in "${pkg_paths[@]}"; do
		pkg_url="${ARTIFACTS_DOMAIN}/${pkg_list_path}/${pkg_path}"

		if fetch "server/tools tgz" "${pkg_url}" --output aerospike-server.tgz; then
			found=true
			break
		fi
	done

	if [ "${found}" = "false" ]; then
		log_warn "Could not fetch pkg - ${pkg_url}"
		exit 1
	fi

	echo "${sha256} aerospike-server.tgz" | sha256sum -c -

	tar xzf aerospike-server.tgz --strip-components=1 -C aerospike

	install_aerospike_server
	install_aerospike_tools_subset

	rm aerospike-server.tgz
	rm -rf aerospike
}

log_debug "ARCH = '${ARCH}'"
log_debug "AEROSPIKE_EDITION = '${AEROSPIKE_EDITION}'"
log_debug "AEROSPIKE_VERSION = '${AEROSPIKE_VERSION}'"
log_debug "AEROSPIKE_SHA_X86_64 = '${AEROSPIKE_SHA_X86_64}'"
log_debug "AEROSPIKE_SHA_AARCH64 = '${AEROSPIKE_SHA_AARCH64}'"
log_debug "AEROSPIKE_TOOLS_VERSION = '${AEROSPIKE_TOOLS_VERSION}'"

bootstrap
