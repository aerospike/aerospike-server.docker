#!/usr/bin/env bash

#----------------------------------------------------------------------
# Sample:
#	All editions and distributions: ./test.sh --all
#   enterprise, debian11 with cleanup: ./test.sh -e enterpise -d debian11 -c
#----------------------------------------------------------------------

set -Eeuo pipefail

source lib/log.sh
source lib/support.sh
source lib/verbose_call.sh
source lib/version.sh

IMAGE_TAG=
CONTAINER=

function usage() {
	echo
	echo "Usage: $0 [-e|--edition EDITION] [-d|--distro DISTRIBUTION] [-a|--all] [-c|--clean] [-h|--help]" 1>&2
	echo
	echo "-e|--edition EDITION: community, enterprise, federal."
	echo "-d|--distro DISTRIBUTION: debian11."
	echo "-a|--all: run test for all the editions and distribution."
	echo "-c|--clean: cleanup the images after the test."
	echo "-h|--help: this help."
	echo
}

function parse_args() {
	CLEAN="false"
	TEST_ALL="false"
	EDITION='enterprise'
	DISTRIBUTION='debian11'

	PARSED_ARGS=$(getopt -a -n test -o che:d:p:a --long clean,help,edition:,distro:,platform:,all -- "$@")
	VALID_ARGS=$?

	if [ "${VALID_ARGS}" != "0" ]; then
		usage
	fi

	eval set -- "${PARSED_ARGS}"
	while true; do
		case "$1" in
		-a | --all)
			TEST_ALL="true"
			shift
			;;
		-c | --clean)
			CLEAN="true"
			shift
			;;
		-e | --edition)
			EDITION=$2
			shift 2
			;;
		-d | --distro)
			DISTRIBUTION=$2
			shift 2
			;;
		--)
			shift
			break
			;;
		-h)
			usage
			exit 0
			;;
		*)
			log_warn "Unexpected option: $1"
			usage
			exit 1
			;;
		esac
	done
}

function run_docker() {
	version=$1

	log_info "------ Running docker image ${IMAGE_TAG} ..."

	if [ "${EDITION}" = "community" ] || version_compare_ge "${version}" "6.1"; then
		verbose_call docker run -td --name "${CONTAINER}" "${PLATFORM/#/"--platform="}" \
			-p 3000:3000 -p 3001:3001 -p 3002:3002 -p 3003:3003 \
			"${IMAGE_TAG}"
	else
		verbose_call docker run -td --name "${CONTAINER}" "${PLATFORM/#/"--platform="}" \
			-p 3000:3000 -p 3001:3001 -p 3002:3002 -p 3003:3003 \
			-v "/$(pwd)/res/":/asfeat/ -e "FEATURE_KEY_FILE=/asfeat/eval_features.conf" \
			"${IMAGE_TAG}"
	fi
}

function try() {
	attempts=$1 # 1 second sleep between attempts.
	shift
	cmd="${*@Q}"

	for ((i = 0; i < attempts; i++)); do
		log_debug "Attempt ${i} for ${cmd}" >&2

		if eval "${cmd}"; then
			return 0
		fi

		sleep 1
	done

	return 1
}

function check_container() {
	local version=$1

	log_info "------ Verifying docker container ..."

	if [ "$(docker container inspect -f '{{.State.Status}}' "${CONTAINER}")" == "running" ]; then
		log_success "Container ${CONTAINER} started and running"
	else
		log_failure "**Container ${CONTAINER} failed to start**"
		exit 1
	fi

	container_platform="$(docker exec -t "${CONTAINER}" bash -c 'stty -onlcr && uname -m')"
	expected_platform="$(supported_platform_to_arch "${PLATFORM}")"

	if [ "${container_platform}" = "${expected_platform}" ]; then
		log_success "Container platform is expected platform '${expected_platform}'"
	else
		log_failure "**Container platform '${container_platform}' does not match expected platform '${expected_platform}'**"
		exit 1
	fi

	if try 10 docker exec -t "${CONTAINER}" bash -c 'pgrep -x asd' >/dev/null; then
		log_success "Aerospike database is running"
	else
		log_failure "**Aerospike database is not running**"
		exit 1
	fi

	if try 5 docker exec -t "${CONTAINER}" bash -c 'asinfo -v status' | grep -qE "^ok"; then
		log_success "Aerospike database is responding"
	else
		log_failure "**Aerospike database is not responding**"
		exit 1
	fi

	build=$(try 5 docker exec -t "${CONTAINER}" bash -c 'asadm -e "enable; asinfo -v build"' | grep -oE "^${version}")

	if [ -n "${build}" ]; then
		log_success "Aerospike database has correct version - '${build}'"
	else
		log_failure "**Aerospike database has incorrect version - '${build}'*"
		exit 1
	fi

	edition=$(try 5 docker exec -t "${CONTAINER}" bash -c 'asadm -e "enable; asinfo -v edition"' | grep -oE "^Aerospike ${EDITION^} Edition")

	if [ -n "${edition}" ]; then
		log_success "Aerospike database has correct edition - '${edition}"
	else
		log_failure "**Aerospike database has incorrect edition - '${edition}'*"
		exit 1
	fi

	log_info "------ Verify docker image completed successfully"
}

function clean_docker() {
	log_info "------ Cleaning up old containers ..."
	verbose_call docker stop "${CONTAINER}"
	verbose_call docker rm -f "${CONTAINER}"
	log_info "------ Cleaning up old containers complete"

	if [ "${CLEAN}" = "true" ]; then
		log_info "------ Cleaning up old images ..."
		verbose_call docker rmi -f "$(docker images "${IMAGE_TAG}" -a -q | sort | uniq)"
		log_info "------ Cleaning up old images complete"
	fi
}

function test_current_edition_distro() {
	local version
	version="$(get_version_from_dockerfile "${DISTRIBUTION}" "${EDITION}")"
	CONTAINER="aerospike-server-${EDITION}"
	local platform_list
	IFS=' ' read -r -a platform_list <<<"$(supported_platforms_for_asd "${version}" "${EDITION}")"

	for platform in "${platform_list[@]}"; do
		short_platform=${platform#*/}
		IMAGE_TAG="aerospike/aerospike-server-${EDITION}-${short_platform}:${version}"
		PLATFORM=${platform}
		run_docker "${version}"
		check_container "${version}"
		clean_docker
	done
}

function main() {
	parse_args "$@"

	if [ "${TEST_ALL}" = "true" ]; then
		local edition_list=('community' 'enterprise' 'federal')

		log_info "------ Testing for all the available editions and distributions"
		for edition in "${edition_list[@]}"; do
			local distribution_list=("${DISTRIBUTION}")

			if [ -z "${DISTRIBUTION}" ]; then
				tmp_list=("$(find "${edition}"/* -maxdepth 0 -type d)")
				distribution_list=("${tmp_list[@]/#"${edition}"\//}")
			fi

			for distribution in "${distribution_list[@]}"; do
				EDITION=$edition
				DISTRIBUTION=$distribution
				log_info "------ Testing for edition=${EDITION} Distribution=${DISTRIBUTION}"
				test_current_edition_distro
			done
		done
	else
		test_current_edition_distro
	fi
}

main "$@"
