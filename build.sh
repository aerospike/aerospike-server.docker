#!/usr/bin/env bash

#-------------------------------------------------------------------------
# build images for test (by the script test.sh) or release (push to docker registry)
# Samples:
#   build and push to docker repo: ./build.sh -p
#   build all images for test: ./build.sh -t
#   build images for specific edition/distribution: ./build.sh -e community -d debian11
#-----------------------------------------------------------------------

set -Eeuo pipefail

source lib/log.sh
source lib/support.sh
source lib/verbose_call.sh

function build_edition() {
	local edition=$1
	local distro=$2
	local platform_list

	log_info "${FUNCNAME[0]} - edition ${edition} distro ${distro}"

	local docker_path="${edition}/${distro}"
	local version
	version="$(grep "ARG AEROSPIKE_VERSION=" "${docker_path}/Dockerfile" | cut -d = -f 2)"

	IFS=' ' read -r -a platform_list <<<"$(supported_platforms_for_asd "${version}" "${edition}")"

	if [ "${g_test_build}" = "true" ]; then
		for platform in "${platform_list[@]}"; do
			log_info "------ building test images for edition=${edition} distro=${distro} platform=${platform}----"
			short_platform=${platform#*/}
			verbose_call docker buildx build --progress plain \
				-t "aerospike/aerospike-server-${edition}-${short_platform}:${version}" \
				-t "aerospike/aerospike-server-${edition}-${short_platform}:latest" \
				"--platform=${platform}" \
				"--load" \
				"${docker_path}"
		done
	elif [ "${g_push_build}" = "true" ]; then
		latest_version="$(find_latest_server_version)"
		lineage="$(echo "${version}" | grep -oE "^[0-9]*(\.[0-9]*){2}")"
		latest_lineage_version="$(find_latest_server_version_for_lineage "${lineage}")"

		printf -v platforms_str '%s,' "${platform_list[@]}"
		platforms_str="${platforms_str%,}"

		log_info "------ building release images for edition=${edition} distro=${distro} platforms=${platforms_str}----"
		# shellcheck disable=SC2046
		verbose_call docker buildx build --progress plain \
			$([ "${latest_version}" = "${version}" ] && echo "-t aerospike/aerospike-server-${edition}:latest") \
			-t "aerospike/aerospike-server-${edition}:${version}" \
			$([ "${latest_lineage_version}" = "${version}" ] && echo "-t aerospike/aerospike-server-${edition}:${lineage}") \
			"--platform=${platforms_str}" \
			"--push" \
			"${docker_path}"
	fi
}

function usage() {
	cat <<EOF
Usage: $0 -h -d <linux distro> -e <server edition>

	-h display this help.
	-d <linux disto> (debian11) only build for this distro.
	-e <server edition> (enterprise|federal|community) only build this server
		edition.
	-t build for invoking test in test.sh
	-p build for release/push to dockerhub
EOF
}

function parse_args() {
	g_linux_distro=
	g_server_edition=
	g_test_build='false'
	g_push_build='false'

	while getopts "hd:e:tp" opt; do
		case "${opt}" in
		h)
			usage
			exit 0
			;;
		d)
			g_linux_distro="${OPTARG}"
			;;
		e)
			g_server_edition="${OPTARG}"
			;;
		t)
			g_test_build='true'
			;;
		p)
			g_push_build='true'
			;;
		*)
			log_warn "** Invalid argument **"
			usage
			exit 1
			;;
		esac
	done

	shift $((OPTIND - 1))

	log_debug "g_linux_distro: '${g_linux_distro}'"
	log_debug "g_server_edition: '${g_server_edition}'"
	log_debug "g_test_build: '${g_test_build}'"
	log_debug "g_push_build: '${g_push_build}'"
}

function main() {
	parse_args "$@"

	local editions=("enterprise" "federal" "community")
	local distro_in=${g_linux_distro}

	if [ -n "${g_server_edition}" ]; then
		editions=("${g_server_edition}")
	fi

	for edition in "${editions[@]}"; do
		local distribution_list=("${distro_in}")

		if [ -z "${distro_in}" ]; then
			tmp_list=("$(find "${edition}"/* -maxdepth 0 -type d)")
			distribution_list=("${tmp_list[@]/#"${edition}"\//}")
		fi

		for distribution in "${distribution_list[@]}"; do
			build_edition "${edition}" "${distribution}"
		done
	done
}

main "$@"
