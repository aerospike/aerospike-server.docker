#
# Aerospike Server Dockerfile
# Version: 7.1.0.21 | Edition: community | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.version="7.1.0.21" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="community"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.1.0.21/aerospike-server-community_7.1.0.21_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="4a855f5901c69fca592c682ee5b3790b06de218c2a8a61ace68998d5ecf4bb1b"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.1.0.21/aerospike-server-community_7.1.0.21_tools-12.1.1_el9_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="16cb5f7a44a1ff032adbf423c6bfb48bae8c0eaedb2cf7855a6a300f487c54b4"


SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh


RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
