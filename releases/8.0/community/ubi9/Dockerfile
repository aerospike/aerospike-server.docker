#
# Aerospike Server Dockerfile
# Version: 8.0.0.13 | Edition: community | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.version="8.0.0.13" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="community"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/8.0.0.13/aerospike-server-community_8.0.0.13_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="845dd2e4a5df320527a1024b807f17a3ea6c372dea9f60c99326467c8d133020"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/8.0.0.13/aerospike-server-community_8.0.0.13_tools-12.1.1_el9_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="2976fa9c21220e71d7b0d918d63bf9297b3a4ba2d450ea64ab6735e3794fdd80"


SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh


RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
