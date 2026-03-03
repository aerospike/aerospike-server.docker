# syntax=docker/dockerfile:1
#
# Aerospike Server Dockerfile
# Version: 8.1.1.1 | Edition: federal | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Federal Server" \
      org.opencontainers.image.version="8.1.1.1" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi9/ubi-minimal:9.4" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.documentation="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.licenses="Proprietary"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"

ARG AEROSPIKE_EDITION="federal"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-federal/8.1.1.1/aerospike-server-federal_8.1.1.1_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="2f9fd1729f51ad4847f5ea8373ed7fc465f47cfb7604562b94a7427ad684d8be"
ARG AEROSPIKE_AARCH64_LINK=""
ARG AEROSPIKE_SHA_AARCH64=""

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh

RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]

