#!/usr/bin/env bash

set -Eeuo pipefail

source lib/log.sh
source lib/version.sh

function support_all_editions() {
	echo "enterprise federal community"
}

function supported_editions_for_asd() {
	local version=$1

	if version_compare_ge "6.0" "${version}"; then
		echo "enterprise community"
		return
	fi

	echo "enterprise federal community"
}

function support_distro_to_base() {
	local distro=$1

	case "${distro}" in
	debian10)
		echo "debian:buster-slim"
		;;
	debian11)
		echo "debian:bullseye-slim"
		;;
	*)
		warn "unsupported distro '${distro}'"
		exit 1
		;;
	esac
}

function supported_distros_for_asd() {
	local version=$1

	if version_compare_ge "6.0" "${version}"; then
		echo "debian10"
		return
	fi

	echo "debian11"
}

function supported_arch_for_asd() {
	local version=$1

	if version_compare_ge "6.2" "${version}"; then
		echo "x86_64"
		return
	fi

	echo "x86_64 aarch64"
}

function supported_platforms_for_asd() {
	local version=$1

	if version_compare_ge "6.2" "${version}"; then
		echo "linux/amd64"
		return
	fi

	echo "linux/amd64 linux/arm64"
}
