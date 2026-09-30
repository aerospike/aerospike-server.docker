
#
# Aerospike Server Dockerfile
#
# https://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:22.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="7.1.0.25" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="enterprise"

ENV AEROSPIKE_LINUX_BASE="ubuntu:22.04"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    ca-certificates \
    procps \
  ; \
  rm -rf /var/lib/apt/lists/*

# Install Aerospike Server and Tools
# hadolint ignore=DL3003,DL3008,DL3041,SC2015
RUN \
  { \
    # Install curl and resolve arch-specific links.
    apt-get update; \
    apt-get install -y --no-install-recommends curl; \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "${ARCH}" = "amd64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static'; \
        tiniSha='d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940'; \
        serverUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/jammy/aerospike-server-enterprise/aerospike-server-enterprise_7.1.0.25-5ubuntu22.04_amd64.deb'; \
        serverSha='f02c3f70689a8e090c1c0048aa20c62ca84c3590d11fbdfe71da51f233489a81'; \
        asadmUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/jammy/aerospike-asadm/aerospike-asadm_5.1.0-2ubuntu22.04_amd64.deb'; \
        asadmSha='97f66a9742b38b1c2f1e4f9a50e822b88f38746a54a889a96a8b88da065238a6'; \
    elif [ "${ARCH}" = "arm64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'; \
        tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'; \
        serverUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/jammy/aerospike-server-enterprise/aerospike-server-enterprise_7.1.0.25-5ubuntu22.04_arm64.deb'; \
        serverSha='1e3459cedcefcc3ce106382d003760b3c8f7a372257d051f254501be0adf5aff'; \
        asadmUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/jammy/aerospike-asadm/aerospike-asadm_5.1.0-2ubuntu22.04_arm64.deb'; \
        asadmSha='178df242b0fb46e59e7e69ac63cec9d89017243832a10abe62c37a698b387b97'; \
    else \
        echo >&2 "error: unsupported architecture '${ARCH}'"; \
        exit 1; \
    fi; \
  }; \
  { \
    # Fetch and install tini.
    curl -fL -o /usr/bin/as-tini-static "${tiniUrl}"; \
    echo "${tiniSha} */usr/bin/as-tini-static" | sha256sum --strict --check -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    # Download server and asadm packages (remote builds only; local builds use COPY).
    # Downloads are named to match the arch-qualified globs used by the install step \
    # below, so remote and pre-staged packages are collected the same way. \
    mkdir -p /tmp/aerospike; \
    if [ -n "${serverUrl}" ]; then \
        curl -fL -o "/tmp/aerospike/aerospike-server-dl_${ARCH}.deb" "${serverUrl}"; \
        echo "${serverSha} */tmp/aerospike/aerospike-server-dl_${ARCH}.deb" | sha256sum --strict --check -; \
    fi; \
    if [ -n "${asadmUrl}" ]; then \
        curl -fL -o "/tmp/aerospike/aerospike-asadm-dl_${ARCH}.deb" "${asadmUrl}"; \
        echo "${asadmSha} */tmp/aerospike/aerospike-asadm-dl_${ARCH}.deb" | sha256sum --strict --check -; \
    fi; \
  }; \
  { \
    # Install Aerospike server.
    # Arch-qualified: a local build stages both arches' packages into \
    # /tmp/aerospike/ through one COPY, and only this arch's may be installed. \
    # Installing server, tools and asadm together lets apt resolve their \
    # dependencies inline. (aerospike-tools may declare a hard Depends on curl; in \
    # that case curl stays installed after the autoremove at the end.) \
    apt-get install -y --no-install-recommends /tmp/aerospike/*_"${ARCH}".deb; \
  }; \
  { \
    # Post-install housekeeping.
    mkdir -p /etc/aerospike /licenses /var/log/aerospike /var/run/aerospike; \
    # /licenses/ is where Red Hat certification expects the license to be. \
    cp /opt/aerospike/doc/LICENSE /licenses/; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
        if [ -f /tmp/aerospike/features.conf ]; then \
            cp /tmp/aerospike/features.conf /etc/aerospike/features.conf; \
        fi; \
    fi; \
    rm -rf /tmp/aerospike; \
    apt-mark auto curl; \
    apt-get autoremove -y --purge; \
    rm -rf /var/lib/apt/lists/*; \
  }; \
  echo "done";

# Add the Aerospike configuration specific to this dockerfile
COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf

# Mount the Aerospike data directory
# VOLUME ["/opt/aerospike/data"]
# Mount the Aerospike config directory
# VOLUME ["/etc/aerospike/"]

# Expose Aerospike ports
#
#   3000 – service port, for client connections
#   3001 – fabric port, for cluster communication
#   3002 – mesh port, for cluster heartbeat
#
EXPOSE 3000 3001 3002

COPY entrypoint.sh /entrypoint.sh

STOPSIGNAL SIGTERM

# Tini init set to restart ASD on SIGUSR1 and terminate ASD on SIGTERM
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Execute the run script in foreground mode
CMD ["asd"]
