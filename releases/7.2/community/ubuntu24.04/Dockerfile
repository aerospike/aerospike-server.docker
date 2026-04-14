#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="7.2.0.16" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="community"

ENV AEROSPIKE_LINUX_BASE="ubuntu:24.04"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.2.0.16/aerospike-server-community_7.2.0.16_tools-12.1.1_ubuntu24.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="df92931d1c3d4816416044d441311b690dd8fdc8dbb05a37de7412949b1fa64c"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.2.0.16/aerospike-server-community_7.2.0.16_tools-12.1.1_ubuntu24.04_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="346b695cf94144d3bfc213c92358aee3583418ca8185064c54e1fddf54456a4a"
ARG AEROSPIKE_COMPAT_LIBS="1"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install Aerospike Server and Tools
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
