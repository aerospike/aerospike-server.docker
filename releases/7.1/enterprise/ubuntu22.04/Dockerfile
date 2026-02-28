#
# Aerospike Server Dockerfile
# Version: 7.1.0.21 | Edition: enterprise | Base: ubuntu22.04
#

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.version="7.1.0.21" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="enterprise"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/7.1.0.21/aerospike-server-enterprise_7.1.0.21_tools-12.1.1_ubuntu22.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="9ab6ad48a37e9b15de616b5c6a80008f71806e076bafa95396302abaeb2308be"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/7.1.0.21/aerospike-server-enterprise_7.1.0.21_tools-12.1.1_ubuntu22.04_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="b20855f5f0cf0c55fa711801aabb21743dd1a0982dc8f14c83f9c127c9f9dda9"


SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh


RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
