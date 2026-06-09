
#
# Aerospike Server Dockerfile
#
# https://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:20.04

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:20.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="5.7.0.32" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="enterprise"

ENV AEROSPIKE_LINUX_BASE="ubuntu:20.04"
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
        pkgLink='https://download.aerospike.com/artifacts/aerospike-server-enterprise/5.7.0.32/aerospike-server-enterprise-5.7.0.32-ubuntu20.04.tgz'; \
        pkgSha='8c8d7d2b7e8ef9728817fc8d8c84e081c5415c789f845bf4a5454c5da305ba93'; \
    elif [ "${ARCH}" = "arm64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'; \
        tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'; \
        pkgLink=''; \
        pkgSha=''; \
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
    # Fetch and unpack server package.
    mkdir -p /tmp/aerospike; \
    curl -fL -o /tmp/aerospike/pkg.tgz "${pkgLink}"; \
    echo "${pkgSha} */tmp/aerospike/pkg.tgz" | sha256sum --strict --check -; \
    tar -xzf /tmp/aerospike/pkg.tgz --strip-components=1 -C /tmp/aerospike; \
  }; \
  { \
    # Install Aerospike server and tools.
    # TGZ contents: newer bundles use underscore server debs; legacy 5.7 uses dotted \
    # names (e.g. aerospike-server-enterprise-5.7.0.32.ubuntu20.04.x86_64.deb) plus \
    # bundled aerospike-tools*.deb. The globs below match both layouts. \
    # apt-get install ./deb pulls many deps; OpenLDAP and libcurl are pinned below because \
    # some legacy server .debs omit Depends that asd still needs after autoremove. \
    apt-get install -y --no-install-recommends \
        /tmp/aerospike/aerospike-server-*.deb \
        /tmp/aerospike/aerospike-tools*.deb; \
    # OpenLDAP client libs (liblber, etc.): required at runtime for enterprise/federal asd. \
    # Some legacy server .debs omit a strict Depends; keep libs after autoremove. \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
        apt-get install -y --no-install-recommends libldap-2.4-2 \
            || apt-get install -y --no-install-recommends libldap-2.5-0; \
        apt-mark manual libldap-2.4-2 2>/dev/null || true; \
        apt-mark manual libldap-2.5-0 2>/dev/null || true; \
    fi; \
  }; \
  { \
    # Post-install housekeeping.
    mkdir -p /etc/aerospike /licenses /var/log/aerospike /var/run/aerospike; \
    cp /tmp/aerospike/LICENSE /licenses/; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
        if [ -f /tmp/aerospike/features.conf ]; then \
            cp /tmp/aerospike/features.conf /etc/aerospike/features.conf; \
        fi; \
    fi; \
    rm -rf /tmp/aerospike; \
    # libcurl: asd links libcurl.so.4; marking curl(1) auto + autoremove can remove libcurl \
    # when server .deb omits Depends (common on legacy packages). Keep the SONAME provider. \
    apt-get install -y --no-install-recommends libcurl4 \
        || apt-get install -y --no-install-recommends libcurl4t64; \
    apt-mark manual libcurl4 2>/dev/null || true; \
    apt-mark manual libcurl4t64 2>/dev/null || true; \
    # Mark curl as auto-installed so autoremove drops it if nothing else depends on it \
    # (aerospike-tools may declare a hard Depends on curl; in that case curl stays). \
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
