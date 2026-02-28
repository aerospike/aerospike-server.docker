#
# Aerospike Server Dockerfile
# Version: 8.0.0.13 | Edition: federal | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Federal Server" \
      org.opencontainers.image.version="8.0.0.13" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="federal"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-federal/8.0.0.13/aerospike-server-federal_8.0.0.13_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="c8c40c4642f05f9e904bb98b877519e45785ced1dba483eedeb35ce93df58aaf"
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
