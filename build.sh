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

	log_info "g_linux_distro: '${g_linux_distro}'"
	log_info "g_server_edition: '${g_server_edition}'"
	log_info "g_test_build: '${g_test_build}'"
	log_info "g_push_build: '${g_push_build}'"

	if [ "${g_test_build}" = "false" ] && [ "${g_push_build}" = "false" ]; then
		log_warn "Must provide either '-t' or '-p' option"
		exit 1
	fi

	if [ "${g_test_build}" = "true" ] && [ "${g_push_build}" = "true" ]; then
		log_warn "Must provide either '-t' or '-p' option, not both"
		exit 1
	fi
}

function main() {
	parse_args "$@"

	local bake_file="bake.hcl"
	local distro_in=${g_linux_distro}
	local targets=
	local params=

	if [ -z "${g_server_edition}" ]; then
		if [ "${g_test_build}" = "true" ]; then
			targets="test"
		elif [ "${g_push_build}" = "true" ]; then
			targets="push"
		fi
	else
		local distribution_list=("${distro_in}")

		if [ -z "${distro_in}" ]; then
			tmp_list=("$(find "${g_server_edition}"/* -maxdepth 0 -type d)")
			distribution_list=("${tmp_list[@]/#"${g_server_edition}"\//}")
		fi

		for distribution in "${distribution_list[@]}"; do
			local version
			version="$(get_version_from_dockerfile "${distribution}" "${g_server_edition}")"
			IFS=' ' read -r -a platform_list <<<"$(support_platforms_for_asd "${version}" "${g_server_edition}")"

			if [ "${g_test_build}" = "true" ]; then
				for platform in "${platform_list[@]}"; do
					short_platform=${platform#*/}
					targets+="${g_server_edition}_${distribution}_${short_platform} "
				done
			elif [ "${g_push_build}" = "true" ]; then
				targets+="${g_server_edition}_${distribution} "
			fi
		done
	fi

	if [ "${g_test_build}" = "true" ]; then
		params="--load"
	elif [ "${g_push_build}" = "true" ]; then
		params="--push"
	fi

	verbose_call docker buildx bake --pull -f "${bake_file}" "${targets}" --progress plain "${params}"
}

main "$@"
