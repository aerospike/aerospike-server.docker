
#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM debian:bullseye-slim

LABEL \
  maintainer="Aerospike, Inc. <developers@aerospike.com>" \
  name="aerospike-community" \
  vendor="Aerospike" \
  version="6.0.0.9" \
  release="2" \
  summary="Aerospike Server Community Edition" \
  description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
  io.k8s.display-name="Aerospike Server Community Edition 6.0.0.9" \
  io.k8s.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions."

ARG DEBUG="false"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="community"

ARG AEROSPIKE_X86_64_LINK="https://artifacts.aerospike.com/aerospike-server-community/6.0.0.9/aerospike-server-community-6.0.0.9-debian11.tgz"
ARG AEROSPIKE_SHA_X86_64="924a5003de112144b0de04777b1e7556020c15d2ae153f510a25e94f94485100"
ARG AEROSPIKE_AARCH64_LINK=""
ARG AEROSPIKE_SHA_AARCH64=""

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Aerospike Server and Tools
RUN <<EOF
#!/usr/bin/env bash

set -Eeuo pipefail

function _log_level() {
	level=$1
	msg=$2

	echo -e "${level} ${BASH_SOURCE[2]}:${BASH_LINENO[1]} - ${msg}" >&2
}

function log_debug() {
	local msg=$1

	if [ "${DEBUG:=}" = "true" ]; then
		_log_level "debug" "${msg}"
	fi
}

function log_warn() {
	local msg=$1

	_log_level "warn" "${msg}"
}

function fetch() {
	local tag=$1
	local link=$2

	log_debug "${tag} - ${link}"

	curl -fsSL "${link}" "${@:3}"
}

function version_compare_ge() {
	v1=$1
	v2=$2

	if [ "$(printf "%s\n%s" "${v1}" "${v2}" | sort -V | head -1)" != "${v1}" ]; then
		return 0
	fi

	return 1
}

function install_bootstrap_dependencies() {
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
}

function remove_bootstrap_dependencies() {
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

function install_aerospike_server_dependencies() {
	if [ "${AEROSPIKE_EDITION}" = "enterprise" ]; then
		apt-get install -y --no-install-recommends \
			libcurl4 \
			libldap-2.4.2
	elif ! version_compare_ge "${VERSION}" "6.0"; then
		apt-get install -y --no-install-recommends \
			libcurl4
	fi
}

function install_aerospike_tools_dependencies() {
	if ! version_compare_ge "${VERSION}" "5.1"; then
		# Tools before 5.1 need python2.
		apt-get install -y --no-install-recommends \
			python2
	elif ! version_compare_ge "${VERSION}" "6.0"; then
		# Tools before 6.0 need python3.
		apt-get install -y --no-install-recommends \
			python3 \
			python3-distutils
	fi

	# Tools after 6.0 bundled their own python interpreter.
}

function install_procps() {
	# The procps package is needed for test using pgrep.
	apt-get install -y --no-install-recommends procps
}

function install_tini() {
	local sha256
	local suffix

	if [ "${ARCH}" = "x86_64" ]; then
		sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940
		suffix=""
	elif [ "${ARCH}" = "aarch64" ]; then
		sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b
		suffix="-arm64"
	else
		log_warn "Unsuported architecture - ${ARCH}"
		exit 1
	fi

	fetch "tini" "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" --output /usr/bin/as-tini-static

	echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -
	chmod +x /usr/bin/as-tini-static
}

function install_aerospike_server() {
	install_aerospike_server_dependencies

	dpkg -i aerospike/aerospike-server-*.deb
	rm -rf /opt/aerospike/bin
}

function install_aerospike_tools_subset() {
	install_aerospike_tools_dependencies

	pushd aerospike/pkg # ar on debian10 doesn't support '--output'
	ar -x ../aerospike-tools*.deb
	popd
	tar xf aerospike/pkg/data.tar.xz -C aerospike/pkg/

	find aerospike/pkg/opt/aerospike/bin/ -user aerospike -group aerospike -exec chown root:root {} +
	mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike

	if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then
		# Since tools release 7.0.5, asadm has been moved from
		# /opt/aerospike/bin/asadm to /opt/aerospike/bin/asadm/asadm
		# (inside an asadm directory).

		mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/
	else
		mkdir /usr/lib/asadm
		mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/
	fi

	ln -s /usr/lib/asadm/asadm /usr/bin/asadm

	if [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ]; then
		# Since tools release 7.1.1, asinfo has been moved from
		# /opt/aerospike/bin/asinfo to /opt/aerospike/bin/asadm/asinfo
		# (inside an asadm directory).
		mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/
	fi

	ln -s /usr/lib/asadm/asinfo /usr/bin/asinfo
}

function install_aerospike_server_and_tools() {
	local pkg_link
	local sha256

	mkdir -p aerospike/pkg

	if [ "${ARCH}" = "x86_64" ]; then
		pkg_link="${AEROSPIKE_X86_64_LINK}"
		sha256="${AEROSPIKE_SHA_X86_64}"
	elif [ "${ARCH}" = "aarch64" ]; then
		pkg_link="${AEROSPIKE_AARCH64_LINK}"
		sha256="${AEROSPIKE_SHA_AARCH64}"
	else
		log_warn "Unsuported architecture - ${ARCH}"
		exit 1
	fi

	if ! fetch "server/tools tgz" "${pkg_link}" --output aerospike-server.tgz; then
		log_warn "Could not fetch pkg - ${pkg_link}"
		exit 1
	fi

	echo "${sha256} aerospike-server.tgz" | sha256sum -c -

	tar xzf aerospike-server.tgz --strip-components=1 -C aerospike

	install_aerospike_server
	install_aerospike_tools_subset

	# These directories are required for backward compatibility.
	mkdir -p /var/{log,run}/aerospike

	# Copy license file to standard location.
	mkdir -p /licenses
	cp aerospike/LICENSE /licenses

	rm aerospike-server.tgz
	rm -rf aerospike
}

function main() {
	ARCH="$(uname -m)"

	log_debug "ARCH = '${ARCH}'"
	log_debug "AEROSPIKE_EDITION = '${AEROSPIKE_EDITION}'"
	log_debug "AEROSPIKE_X86_64_LINK = '${AEROSPIKE_X86_64_LINK}'"
	log_debug "AEROSPIKE_SHA_X86_64 = '${AEROSPIKE_SHA_X86_64}'"
	log_debug "AEROSPIKE_AARCH64_LINK = '${AEROSPIKE_AARCH64_LINK}'"
	log_debug "AEROSPIKE_SHA_AARCH64 = '${AEROSPIKE_SHA_AARCH64}'"

	#DISTRO="$(grep -oE "debian[0-9]+(_x86_64)?[.]tgz$" <<<"${AEROSPIKE_X86_64_LINK}" | cut -d'.' -f1 | grep -oE "debian[0-9]+")"
	VERSION="$(grep -oE "/[0-9]+([.][0-9]+){2,3}/" <<<"${AEROSPIKE_X86_64_LINK}" | tr -d '/')"

	install_bootstrap_dependencies
	install_tini
	install_aerospike_server_and_tools
	install_procps
	remove_bootstrap_dependencies
}

main
EOF

# Add the Aerospike configuration specific to this dockerfile
COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf

# Mount the Aerospike data directory
# VOLUME ["/opt/aerospike/data"]
# Mount the Aerospike config directory
# VOLUME ["/etc/aerospike/"]

# Expose Aerospike ports
#
#   3000 – service port, for client connections
#   3001 – fabric port, for cluster communication
#   3002 – mesh port, for cluster heartbeat
#
EXPOSE 3000 3001 3002

COPY entrypoint.sh /entrypoint.sh

# Tini init set to restart ASD on SIGUSR1 and terminate ASD on SIGTERM
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Execute the run script in foreground mode
CMD ["asd"]
