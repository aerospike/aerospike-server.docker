#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:22.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.licenses="Proprietary" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="7.1.0.22" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="enterprise"

ENV AEROSPIKE_LINUX_BASE="ubuntu:22.04"
ARG AEROSPIKE_X86_64_LINK="/Users/phucvinh/aerospike/server-docker/DOI-Rejection-fix/aerospike-server.docker/artifacts/signed-artifacts/aerospike-server-enterprise-TEST_7.1.0.22-12ubuntu22.04_amd64.deb"
ARG AEROSPIKE_SHA_X86_64="ffb933219d736e5ae101fd769df0760623061f05f6ccd0a218c7b37b87a3f80f"
ARG AEROSPIKE_AARCH64_LINK="/Users/phucvinh/aerospike/server-docker/DOI-Rejection-fix/aerospike-server.docker/artifacts/signed-artifacts/aerospike-server-enterprise-TEST_7.1.0.22-12ubuntu22.04_arm64.deb"
ARG AEROSPIKE_SHA_AARCH64="daf925ef92de5668eb83e8c834d578716378f7fe93da19171989752e3113a2cd"
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
COPY features.conf /etc/aerospike/features.conf

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
