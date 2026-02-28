#
# Aerospike Server Dockerfile
# Version: 7.1.0.21 | Edition: community | Base: ubuntu22.04
#

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.version="7.1.0.21" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="community"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.1.0.21/aerospike-server-community_7.1.0.21_tools-12.1.1_ubuntu22.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="cb558623868e5607ad5c1f58d94b41ff6d056479433f3df47c2ce70688dc2080"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.1.0.21/aerospike-server-community_7.1.0.21_tools-12.1.1_ubuntu22.04_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="30cb6827a0f4fd50524f6f5064aae52fb7f2f0a9399bc7e285bf62b19dae1d95"


SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh


RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
