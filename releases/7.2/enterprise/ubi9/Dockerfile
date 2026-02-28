#
# Aerospike Server Dockerfile
# Version: 7.2.0.15 | Edition: enterprise | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.version="7.2.0.15" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="enterprise"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/7.2.0.15/aerospike-server-enterprise_7.2.0.15_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="726e48dd332d1225d66602d80d8a7f8ab06f8fbd58f1eb34c54127adf1ec7ab7"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/7.2.0.15/aerospike-server-enterprise_7.2.0.15_tools-12.1.1_el9_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="61b98583e32b36e831127930d717b51035816199cf79f5a585f9d87997fd6059"


SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh


RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
