# syntax=docker/dockerfile:1
#
# Aerospike Server Dockerfile
# Version: 8.1.1.1 | Edition: enterprise | Base: ubuntu24.04
#

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.version="8.1.1.1" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.documentation="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.licenses="Proprietary"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"

ARG AEROSPIKE_EDITION="enterprise"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.1.1.1/aerospike-server-enterprise_8.1.1.1_tools-12.1.1_ubuntu24.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="a2990f0970a7ca1bdec8068109dc0573ca975c5dd5d014a9a6f1b0a178849625"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.1.1.1/aerospike-server-enterprise_8.1.1.1_tools-12.1.1_ubuntu24.04_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="1ccb5d3a9cb396ce6dcb58d24d71b2a5eb46f29ec3c24b62472318c02e668d4d"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh

RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]

