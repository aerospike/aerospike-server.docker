
#
# Aerospike Server Dockerfile
#
# https://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.1.2.0" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="enterprise"

ENV AEROSPIKE_LINUX_BASE="ubuntu:24.04"

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
        pkgLink='https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.1.2.0/aerospike-server-enterprise_8.1.2.0_tools-13.0.0_ubuntu24.04_x86_64.tgz'; \
        pkgSha='64397bf042e12c52c9e06189a5fbad86efb7d5c405ba1a4736b55d8ab5ee18b8'; \
    elif [ "${ARCH}" = "arm64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'; \
        tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'; \
        pkgLink='https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.1.2.0/aerospike-server-enterprise_8.1.2.0_tools-13.0.0_ubuntu24.04_aarch64.tgz'; \
        pkgSha='30ebebdd07fe0b7a924433dfde3d6dce6d8fe0841a47cdcf427b14162d83e087'; \
    else \
        echo >&2 "error: unsupported architecture '${ARCH}'"; \
        exit 1; \
    fi; \
    if [ -z "${pkgLink}" ]; then \
        echo >&2 "error: no package available for edition '${AEROSPIKE_EDITION}' on architecture '${ARCH}'"; \
        exit 1; \
    fi; \
  }; \
  { \
    # Fetch and install tini.
    curl -fL -o /usr/bin/as-tini-static "${tiniUrl}"; \
    echo "${tiniSha}  /usr/bin/as-tini-static" | sha256sum --check -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    # Fetch and unpack server package.
    mkdir -p /tmp/aerospike; \
    curl -fL -o /tmp/aerospike/pkg.tgz "${pkgLink}"; \
    echo "${pkgSha}  /tmp/aerospike/pkg.tgz" | sha256sum --check -; \
    tar -xzf /tmp/aerospike/pkg.tgz --strip-components=1 -C /tmp/aerospike; \
  }; \
  { \
    # Install Aerospike and enterprise dependencies.
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
        # LDAP package name differs across Ubuntu releases; install whichever is present. \
        for _ldap_pkg in libldap2 libldap-2.5-0 libldap-2.4-2; do \
            if apt-cache show "${_ldap_pkg}" >/dev/null 2>&1; then \
                apt-get install -y --no-install-recommends "${_ldap_pkg}"; \
                break; \
            fi; \
        done; \
    fi; \
    apt-get install -y --no-install-recommends \
        /tmp/aerospike/aerospike-server-*.deb \
        /tmp/aerospike/aerospike-tools*.deb; \
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
