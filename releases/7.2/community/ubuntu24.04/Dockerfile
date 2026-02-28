#
# Aerospike Server Dockerfile
# Version: 7.2.0.15 | Edition: community | Base: ubuntu24.04
#

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.version="7.2.0.15" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="community"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.2.0.15/aerospike-server-community_7.2.0.15_tools-12.1.1_ubuntu24.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="77bf8cfa9e59f7d014722d9c30e0814c71b9a8ef17291785d23cf70bada15228"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.2.0.15/aerospike-server-community_7.2.0.15_tools-12.1.1_ubuntu24.04_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="158e2a8f652122a7f7d9c01214ea5d0d4117571bf5fd899f91b74230a71f95ac"


SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh


RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
