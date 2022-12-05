#!/usr/bin/env bash

set -Eeuo pipefail

source lib/fetch.sh
source lib/log.sh
source lib/support.sh
source lib/version.sh

function run_template() {
	local distro=$1
	local edition=$2

	log_info "distro '${distro}' edition '${edition}'"

	local server_version="${g_server_version}"
	local tools_version="${g_tools_version}"

	if [ -z "${tools_version}" ]; then
		tools_version=$(find_latest_tools_version_for_server "${distro}" "${edition}" "${server_version}")
	fi

	DEBUG="${DEBUG:=false}"
	LINUX_BASE="$(support_distro_to_base "${distro}")"
	AEROSPIKE_VERSION="${server_version}"
	CONTAINER_RELEASE="${g_container_release}"
	AEROSPIKE_EDITION="${edition}"
	AEROSPIKE_DESCRIPTION="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions."
	AEROSPIKE_X86_64_LINK="$(get_package_link "${distro}" "${edition}" "${server_version}" "${tools_version}" "x86_64")"
	AEROSPIKE_SHA_X86_64="$(fetch_package_sha "${distro}" "${edition}" "${server_version}" "${tools_version}" "x86_64")"
	AEROSPIKE_AARCH64_LINK="$(get_package_link "${distro}" "${edition}" "${server_version}" "${tools_version}" "aarch64")"
	AEROSPIKE_SHA_AARCH64="$(fetch_package_sha "${distro}" "${edition}" "${server_version}" "${tools_version}" "aarch64")"

	log_info "DEBUG: '${DEBUG}'"
	log_info "LINUX_BASE: '${LINUX_BASE}'"
	log_info "AEROSPIKE_VERSION: '${AEROSPIKE_VERSION}'"
	log_info "CONTAINER_RELEASE: '${CONTAINER_RELEASE}'"
	log_info "AEROSPIKE_EDITION: '${AEROSPIKE_EDITION}'"
	log_info "AEROSPIKE_DESCRIPTION: '${AEROSPIKE_DESCRIPTION}'"
	log_info "AEROSPIKE_X86_64_LINK: '${AEROSPIKE_X86_64_LINK}'"
	log_info "AEROSPIKE_SHA_X86_64: '${AEROSPIKE_SHA_X86_64}'"
	log_info "AEROSPIKE_AARCH64_LINK: '${AEROSPIKE_AARCH64_LINK}'"
	log_info "AEROSPIKE_SHA_AARCH64: '${AEROSPIKE_SHA_AARCH64}'"

	local target_path="${edition}/${distro}"

	copy_template "template" "${target_path}"
	bash_eval_templates "${target_path}"
}

function copy_template() {
	local template_path=$1
	local target_path=$2

	log_debug "${template_path} to ${target_path}"

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
		log_debug "${line}"

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
Usage: $0 e|h|r -r <container release> -s <server version> -t <tools version>

    -e Edition to update
    -g Collects version information form 'git describe --abbrev=0'
    -h Display this help.
    -r <container release> Use if re-releasing an image - should increment by
        one for each re-release.
    -s <server version> Use this version instead of scraping the latest version
        from artifacts.
    -t <tools version> Use this version instead of scraping the latest version
        for a particular server version from artifacts.
EOF
}

function parse_args() {
	g_server_edition=
	g_server_version=
	g_container_release='1'
	g_tools_version=

	while getopts "e:ghr:s:t:" opt; do
		case "${opt}" in
		e)
			g_server_edition="${OPTARG}"
			;;
		h)
			usage
			exit 0
			;;
		g)
			git_describe="$(git describe --abbrev=0)"

			if grep -q "_" <<<"${git_describe}"; then
				g_server_version="$(cut -sd _ -f 1 <<<"${git_describe}")"
				g_container_release="$(cut -sd _ -f 2 <<<"${git_describe}")"

				if [ "${g_container_release}" = "1" ]; then
					log_warn "Suffix '_1' is not allowed in tag '${git_describe}'"
					exit 1
				fi
			else
				g_server_version="${git_describe}"
				g_container_release='1'
			fi
			;;
		r)
			g_container_release="${OPTARG}"
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

	IFS=' ' read -r -a distros <<<"$(support_distros_for_asd "${g_server_version}")"

	if [ -z "${g_server_edition}" ]; then
		IFS=' ' read -r -a editions <<<"$(support_editions_for_asd "${g_server_version}")"
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
