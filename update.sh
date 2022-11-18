#!/usr/bin/env bash

set -Eeuo pipefail

source lib/fetch.sh
source lib/log.sh
source lib/support.sh
source lib/version.sh

function run_template() {
	local distro=$1
	local edition=$2

	log_info "${FUNCNAME[0]} - distro '${distro}' edition '${edition}'"

	local server_version="${g_server_version}"
	local tools_version="${g_tools_version}"

	if [ -z "${tools_version}" ]; then
		tools_version=$(find_latest_tools_version_for_server "${distro}" "${edition}" "${server_version}")
	fi

	local sha_x86_64
	sha_x86_64=$(fetch_package_sha "${distro}" "${edition}" "${server_version}" "${tools_version}" "x86_64")
	local sha_aarch64
	sha_aarch64=$(fetch_package_sha "${distro}" "${edition}" "${server_version}" "${tools_version}" "aarch64")

	DEBUG=${DEBUG:=false}
	LINUX_DISTRO=${distro}
	LINUX_BASE=$(support_distro_to_base "${distro}")
	AEROSPIKE_EDITION=${edition}
	AEROSPIKE_VERSION=${server_version}
	AEROSPIKE_SHA_X86_64=${sha_x86_64}
	AEROSPIKE_SHA_AARCH64=${sha_aarch64}
	AEROSPIKE_TOOLS_VERSION=${tools_version}

	log_info "DEBUG '${DEBUG}'"
	log_info "LINUX_DISTRO '${LINUX_DISTRO}'"
	log_info "LINUX_BASE '${LINUX_BASE}'"
	log_info "ARTIFACTS_DOMAIN '${ARTIFACTS_DOMAIN}'"
	log_info "AEROSPIKE_EDITION: '${AEROSPIKE_EDITION}'"
	log_info "AEROSPIKE_VERSION: '${AEROSPIKE_VERSION}'"
	log_info "AEROSPIKE_TOOLS_VERSION: '${AEROSPIKE_TOOLS_VERSION}'"
	log_info "AEROSPIKE_SHA_X86_64: '${AEROSPIKE_SHA_X86_64}'"
	log_info "AEROSPIKE_SHA_AARCH64: '${AEROSPIKE_SHA_AARCH64}'"

	local target_path="${edition}/${distro}"

	copy_template "template" "${target_path}"
	bash_eval_templates "${target_path}"
}

function copy_template() {
	local template_path=$1
	local target_path=$2

	log_debug "${FUNCNAME[0]} - ${template_path} to ${target_path}"

	rm -rf "${target_path}"
	cp -r "${template_path}" "${target_path}"
}

function bash_eval_templates() {
	local target_path=$1

	while IFS= read -r -d '' template_file; do
		target_file="${template_file%.template}"
		bash_eval_template "${template_file}" "${target_file}"
	done < <(find "${target_path}" -type f -name "*.template" -print0)
}

function bash_eval_template() {
	local template_file=$1
	local target_file=$2

	echo "" >"${target_file}"

	while IFS= read -r line; do
		if grep -qE "[$][(]|[{]" <<<"${line}"; then
			local update
			update=$(eval echo "\"${line}\"") || exit 1
			grep -qE "[^[:space:]]*" <<<"${update}" && echo "${update}" >>"${target_file}"
		else
			echo "${line}" >>"${target_file}"
		fi
	done <"${template_file}"

	rm "${template_file}"
}

function usage() {
	cat <<EOF
Usage: $0 e|h|r -s <server version> -t <tools version>

	-e Edition to update
	-h display this help.
	-r For a new release, use the current git tag as the server version.
	-s <server version> use this version instead of scraping the latest version
		from artifacts.
	-t <tools version> use this version instead of scraping the latest version
		for a particular server version from artifacts.
EOF
}

function parse_args() {
	g_server_edition=
	g_server_version=
	g_tools_version=

	while getopts "e:hrs:t:" opt; do
		case "${opt}" in
		e)
			g_server_edition="${OPTARG}"
			;;
		h)
			usage
			exit 0
			;;
		r)
			# TODO - can we only do this when run from github actions?
			git fetch --unshallow || true
			git fetch --tags || true
			g_server_version=$(git describe | cut -d - -f 1)
			;;
		s)
			g_server_version="${OPTARG}"
			;;
		t)
			g_tools_version="${OPTARG}"
			;;
		*)
			log_warn "** Invalid argument **"
			usage
			exit 1
			;;
		esac
	done

	shift $((OPTIND - 1))
}

function main() {
	parse_args "$@"

	if [ -z "${g_server_version}" ]; then
		g_server_version=$(find_latest_server_version)
	else
		g_server_version=$(find_latest_server_version_for_lineage "${g_server_version}")
	fi

	local distros
	local editions
	local all_editions

	IFS=' ' read -r -a distros <<<"$(supported_distros_for_asd "${g_server_version}")"

	if [ -z "${g_server_edition}" ]; then
		IFS=' ' read -r -a editions <<<"$(supported_editions_for_asd "${g_server_version}")"
	else
		editions=("${g_server_edition}")
	fi

	IFS=' ' read -r -a all_editions <<<"$(support_all_editions)"

	for edition in "${all_editions[@]}"; do
		find "${edition}"/* -maxdepth 0 -type d -exec rm -rf {} \;
	done

	for edition in "${editions[@]}"; do
		for distro in "${distros[@]}"; do
			run_template "${distro}" "${edition}"
		done
	done
}

main "$@"
