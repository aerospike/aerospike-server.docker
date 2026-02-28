#
# Aerospike Server Dockerfile
# Version: 7.1.0.21 | Edition: federal | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Federal Server" \
      org.opencontainers.image.version="7.1.0.21" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="federal"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-federal/7.1.0.21/aerospike-server-federal_7.1.0.21_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="5babb6c82e7695912abba597c4be6848476cff0610b4a61ea9fdc3787cf77f0f"
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
