#
# Aerospike Server Dockerfile
# Version: 7.2.0.15 | Edition: community | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.version="7.2.0.15" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="community"
ARG AEROSPIKE_PKG_FORMAT="tgz"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.2.0.15/aerospike-server-community_7.2.0.15_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="4500cf75bfa7f0209b865f8a914eccec6e765d28ff5c6875c717f625cc2640cd"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.2.0.15/aerospike-server-community_7.2.0.15_tools-12.1.1_el9_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="f04856e46336ca4b1488749e882c0a5b7bb37335de500240e1e110c985a9e4e9"


SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

COPY install.sh /tmp/install.sh


RUN /bin/bash /tmp/install.sh && rm /tmp/install.sh

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
