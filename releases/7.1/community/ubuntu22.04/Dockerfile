#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:22.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="7.1.0.22" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="community"

ENV AEROSPIKE_LINUX_BASE="ubuntu:22.04"
ARG AEROSPIKE_X86_64_LINK="/Users/phucvinh/aerospike/server-docker/DOI-Rejection-fix/aerospike-server.docker/artifacts/signed-artifacts/aerospike-server-community-TEST_7.1.0.22-12ubuntu22.04_amd64.deb"
ARG AEROSPIKE_SHA_X86_64="972c625c1cc33051d4a83fd87add0b8f21b6e678d3d35456f00629195be54db0"
ARG AEROSPIKE_AARCH64_LINK="/Users/phucvinh/aerospike/server-docker/DOI-Rejection-fix/aerospike-server.docker/artifacts/signed-artifacts/aerospike-server-community-TEST_7.1.0.22-12ubuntu22.04_arm64.deb"
ARG AEROSPIKE_SHA_AARCH64="799ce19b84de92f7faac0527c2f29f4110b6df452df10136d8ae696463a0b98b"
ARG AEROSPIKE_COMPAT_LIBS="0"
ARG AEROSPIKE_LOCAL_PKG="1"
SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install Aerospike Server and Tools
COPY server_amd64.deb server_amd64.deb.sha256 server_arm64.deb server_arm64.deb.sha256 /tmp/
COPY install.sh /tmp/install.sh
# hadolint ignore=DL3008,DL3041
RUN bash /tmp/install.sh && rm -f /tmp/install.sh

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
