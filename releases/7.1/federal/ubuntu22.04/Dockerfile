#
# Aerospike Server Dockerfile
# Version: 7.1.0.21 | Edition: federal | Base: ubuntu22.04
#

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Aerospike Federal Server" \
      org.opencontainers.image.version="7.1.0.21" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="federal"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-federal/7.1.0.21/aerospike-server-federal_7.1.0.21_tools-12.1.1_ubuntu22.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="957fadfb46bba1aeb3e3fce33588b645cab546d6259af49c217df6246942d46a"
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
