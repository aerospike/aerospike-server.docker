
#
# Aerospike Server Dockerfile
#
# https://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Aerospike Community Server" \
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
ARG AEROSPIKE_EDITION="community"

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
    # Aerospike publishes some packages (notably aerospike-asadm) with the kernel \
    # arch spelling rather than the dpkg one, so both are matched when collecting. \
    if [ "${ARCH}" = "amd64" ]; then \
        ALT_ARCH="x86_64"; \
    elif [ "${ARCH}" = "arm64" ]; then \
        ALT_ARCH="aarch64"; \
    fi; \
    if [ "${ARCH}" = "amd64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static'; \
        tiniSha='d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940'; \
        serverUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/jammy/aerospike-server-community/aerospike-server-community_7.1.0.25-5ubuntu22.04_amd64.deb'; \
        serverSha='da92071b3254ee77a50aa905d37b4f4355003792e852b15f34c30a6454d355bd'; \
        asadmUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/jammy/aerospike-asadm/aerospike-asadm_5.0.3-5ubuntu22.04_amd64.deb'; \
        asadmSha='6ed4c26d7cff26ffc16b0082642e0744c8244668de42862239cb4dc1241d56c3'; \
    elif [ "${ARCH}" = "arm64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'; \
        tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'; \
        serverUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/jammy/aerospike-server-community/aerospike-server-community_7.1.0.25-5ubuntu22.04_arm64.deb'; \
        serverSha='28203aede74d8fce6be0de32bc403f79465cf7d3bb5891406122469176e03668'; \
        asadmUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/jammy/aerospike-asadm/aerospike-asadm_5.0.3-5ubuntu22.04_arm64.deb'; \
        asadmSha='445088ab23441edddd6938c6e3616d557ef36ebde773e241ec55e0a11642bc25'; \
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
    # Collect all arch-matching packages in /tmp/aerospike/: \
    #   - aerospike-server-*_${ARCH}.deb  (required) \
    #   - aerospike-tools-*_${ARCH}.deb   (optional; staged when server declares a \
    #                                      hard Depends on aerospike-tools) \
    #   - aerospike-asadm*_${ARCH}.deb    (optional; downloaded or staged above, \
    #                                      including arch-independent _all.deb) \
    # Installing them together lets apt resolve the dependencies inline. \
    # (aerospike-tools may also declare a hard Depends on curl; in that case curl \
    # stays installed after the autoremove at the end.) \
    pkgs=(); \
    serverFound=false; \
    for f in /tmp/aerospike/aerospike-server-*_"${ARCH}".deb \
        /tmp/aerospike/aerospike-server-*_"${ALT_ARCH}".deb; do \
        if [ -f "${f}" ]; then \
            pkgs+=("${f}"); \
            serverFound=true; \
        fi; \
    done; \
    # The server package is the only required one; asadm/tools alone must never \
    # produce an image, so the guard tracks the server specifically. \
    if [ "${serverFound}" = false ]; then \
        echo >&2 "error: no server package found in /tmp/aerospike/ for arch '${ARCH}'"; \
        exit 1; \
    fi; \
    for f in /tmp/aerospike/aerospike-tools-*_"${ARCH}".deb \
        /tmp/aerospike/aerospike-tools-*_"${ALT_ARCH}".deb \
        /tmp/aerospike/aerospike-asadm*_"${ARCH}".deb \
        /tmp/aerospike/aerospike-asadm*_"${ALT_ARCH}".deb \
        /tmp/aerospike/aerospike-asadm*_all.deb; do \
        if [ -f "${f}" ]; then pkgs+=("${f}"); fi; \
    done; \
    apt-get install -y --no-install-recommends "${pkgs[@]}"; \
  }; \
  { \
    # Post-install housekeeping.
    mkdir -p /etc/aerospike /licenses /var/log/aerospike /var/run/aerospike; \
    # The server package ships its license at /opt/aerospike/doc/LICENSE; the \
    # image has always published it at /licenses/ (a Red Hat certification \
    # requirement on UBI). Warn loudly rather than fail: an absent file means the \
    # packaging changed, and the warning names the invariant to restore. \
    if [ -f /opt/aerospike/doc/LICENSE ]; then \
        cp /opt/aerospike/doc/LICENSE /licenses/; \
    else \
        echo >&2 "warning: /opt/aerospike/doc/LICENSE not found - /licenses/ left empty"; \
    fi; \
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
