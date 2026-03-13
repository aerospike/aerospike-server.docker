# syntax=docker/dockerfile:1
#
# Aerospike Server Dockerfile
# Version: 8.1.1.1 | Edition: community | Base: ubuntu24.04
#

FROM ubuntu:24.04@sha256:d1e2e92c075e5ca139d51a140fff46f84315c0fdce203eab2807c7e495eff4f9

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.version="8.1.1.1" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.documentation="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.licenses="Apache-2.0"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"

ARG AEROSPIKE_EDITION="community"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/8.1.1.1/aerospike-server-community_8.1.1.1_tools-12.1.1_ubuntu24.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="bbbbb10b08d67391058da8c88df06da027b25f7bd4bf44959a14a78c392d10a7"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/8.1.1.1/aerospike-server-community_8.1.1.1_tools-12.1.1_ubuntu24.04_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="5129d72c4dceb753a95f49a2cfc29788dd55acfb140ff4cee7431824301b13c0"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh

RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]

