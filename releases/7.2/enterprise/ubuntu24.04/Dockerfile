#
# Aerospike Server Dockerfile
# Version: 7.2.0.15 | Edition: enterprise | Base: ubuntu24.04
#

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.version="7.2.0.15" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="enterprise"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/7.2.0.15/aerospike-server-enterprise_7.2.0.15_tools-12.1.1_ubuntu24.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="17c9338e23502bae70ef59e5904e8162e3cadf28f51d3220b0ddece6db9252f0"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/7.2.0.15/aerospike-server-enterprise_7.2.0.15_tools-12.1.1_ubuntu24.04_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="fe03f5d8c7543aa3c33794387b76320ca00431c97f79c4fdeac04f1211db7a1d"


SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh


RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
