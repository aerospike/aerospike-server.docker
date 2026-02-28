#
# Aerospike Server Dockerfile
# Version: 8.1.1.1 | Edition: community | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.version="8.1.1.1" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="community"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/8.1.1.1/aerospike-server-community_8.1.1.1_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="abde13452f22cbcbedd9f8c8c852722101270e1178bf690367eac99b5cf0f345"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/8.1.1.1/aerospike-server-community_8.1.1.1_tools-12.1.1_el9_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="56382b5f3a9d5f782e58a4e7145bc887f54d0d9482f61388554a115b08218123"


SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh


RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
