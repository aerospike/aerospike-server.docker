#!/usr/bin/env bash

set -Eeuo pipefail

source lib/fetch.sh

ARTIFACTS_DOMAIN=${ARTIFACTS_DOMAIN:="https://artifacts.aerospike.com"}

function version_compare_ge() {
	v1=$1
	v2=$2

	if [ "$(printf "%s\n%s" "${v1}" "${v2}" | sort -V | head -1)" != "${v1}" ]; then
		return 0
	fi

	return 1
}

function find_latest_server_version() {
	local server_version

	# Note - we assume every release will have a enterprise component.
	server_version="$(
		fetch "${FUNCNAME[0]}" "${ARTIFACTS_DOMAIN}/aerospike-server-enterprise/" |
			grep -oE '<a href="[0-9.-]+[-]*.*/"' |
			sed -r 's!.*<a href="([0-9.-]+[-]*.*)/".*!\1!' |
			sort -V |
			tail -1
	)"

	echo "${server_version}"
}

function find_latest_server_version_for_lineage() {
	local lineage=$1

	local server_version

	# Note - we assume every release will have a enterprise component.
	server_version="$(
		fetch "${FUNCNAME[0]}" "${ARTIFACTS_DOMAIN}/aerospike-server-enterprise/${lineage}/" |
			grep -oE "aerospike-server-enterprise[-_][0-9.]+" |
			grep -oE "[0-9.]+$" |
			sort -V |
			head -1
	)"

	echo "${server_version}"
}

function find_latest_tools_version_for_server() {
	local distro=$1
	local edition=$2
	local server_version=$3

	if version_compare_ge "6.2" "${server_version}"; then
		# Tools version not part of package name prior to 6.2.
		log_debug "${FUNCNAME[0]} - prior to 6.2"
		echo ""
		return
	fi

	log_debug "${FUNCNAME[0]} - newer than 6.2"

	local tools_version
	tools_version="$(
		fetch "${FUNCNAME[0]}" "${ARTIFACTS_DOMAIN}/aerospike-server-${edition}/${server_version}/" |
			grep -oE "_tools-[0-9.-]+(-g[a-f0-9]{7})?_${distro}_x86_64.tgz" |
			cut -d _ -f 2 |
			sort -V |
			tail -1
	)"

	echo "${tools_version#tools-}"
}

function fetch_package_sha() {
	local distro=$1
	local edition=$2
	local server_version=$3
	local tools_version=$4
	local arch=$5

	local url

	if version_compare_ge "6.2" "${server_version}"; then
		if [ "${arch}" = "aarch64" ]; then
			# Did not support aarch64 prior to 6.2.
			echo ""
			return
		fi

		# Package names prior to 6.2.
		url="${ARTIFACTS_DOMAIN}/aerospike-server-${edition}/${server_version}/aerospike-server-${edition}-${server_version}-${distro}.tgz.sha256"
	else
		# Package names 6.2 and later.
		url="${ARTIFACTS_DOMAIN}/aerospike-server-${edition}/${server_version}/aerospike-server-${edition}_${server_version}_tools-${tools_version}_${distro}_${arch}.tgz.sha256"
	fi

	fetch "${FUNCNAME[0]}" "${url}" | cut -f 1 -d ' '
}
