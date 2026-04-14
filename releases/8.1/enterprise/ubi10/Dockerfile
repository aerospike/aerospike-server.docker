#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM registry.access.redhat.com/ubi10/ubi-minimal:10.0

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi10/ubi-minimal:10.0" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.licenses="Proprietary" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.1.1.2" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="enterprise"

ENV AEROSPIKE_LINUX_BASE="registry.access.redhat.com/ubi10/ubi-minimal:10.0"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.1.1.2/aerospike-server-enterprise_8.1.1.2_tools-12.1.1_el10_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="8c76a7a906686bf80c5dc17b43901ac3d03c262f1b8bef9c69a65c50fbb1f0c1"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.1.1.2/aerospike-server-enterprise_8.1.1.2_tools-12.1.1_el10_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="212b7df6f28e24713bb6411ded68b427044ac84d7c203fe9af6c242a2ddbf0f9"
ARG AEROSPIKE_COMPAT_LIBS="0"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install Aerospike Server and Tools
COPY install.sh /tmp/install.sh
# hadolint ignore=DL3003,DL3008,DL3041,SC2015
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
