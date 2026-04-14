#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi9/ubi-minimal:9.7" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.licenses="Proprietary" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.0.0.14" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="enterprise"

ENV AEROSPIKE_LINUX_BASE="registry.access.redhat.com/ubi9/ubi-minimal:9.7"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.14/aerospike-server-enterprise_8.0.0.14_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="8d118bcc8d2187e19c306a13098e655133bb4f37210d8b10abd5c741c340cd6b"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.14/aerospike-server-enterprise_8.0.0.14_tools-12.1.1_el9_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="bb28c5024535f85e0ff8c17926866746cc9c44fa203a3dbef1e35a051c6fcc5e"
ARG AEROSPIKE_COMPAT_LIBS="0"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install Aerospike Server and Tools
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
