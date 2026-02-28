#
# Aerospike Server Dockerfile
# Version: 8.0.0.13 | Edition: enterprise | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.version="8.0.0.13" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="enterprise"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.13/aerospike-server-enterprise_8.0.0.13_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="ada7a14385a3144b7e894cf8ec143eb6eae70d1eb9495eb33cecffbb1cad5974"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.0.0.13/aerospike-server-enterprise_8.0.0.13_tools-12.1.1_el9_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="d9d5c8121a61cb888e880388c4b3eea46a714055b1e9ca631b6f259e62ab6bd1"


SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh


RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
