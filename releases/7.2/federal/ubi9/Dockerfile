#
# Aerospike Server Dockerfile
# Version: 7.2.0.15 | Edition: federal | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Federal Server" \
      org.opencontainers.image.version="7.2.0.15" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="federal"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-federal/7.2.0.15/aerospike-server-federal_7.2.0.15_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="d04cd1ac95818fe0b45fbb037b542cca140805b80ba7f05f1846d780e4e310b2"
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
