
#
# Aerospike Server Dockerfile
#
# https://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.0.0.20" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="community"

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
        serverUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/noble/aerospike-server-community/aerospike-server-community_8.0.0.20-15ubuntu24.04_amd64.deb'; \
        serverSha='e79c773ac55726147c18bad2f5f24dbceabe32ef9508a303ee0eeaab6b96dcfd'; \
        asadmUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/noble/aerospike-asadm/aerospike-asadm_5.0.3-5ubuntu24.04_amd64.deb'; \
        asadmSha='2ce43be9b1a3fa16a151daa35127641c8f089380d05e83625c595a03aa98d333'; \
    elif [ "${ARCH}" = "arm64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'; \
        tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'; \
        serverUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/noble/aerospike-server-community/aerospike-server-community_8.0.0.20-15ubuntu24.04_arm64.deb'; \
        serverSha='b5128c0ae8529026a97e9d2d49a084280d808915e1046750f05edc780158d279'; \
        asadmUrl='https://aerospike.jfrog.io/artifactory/database-deb-prod-public-local/pool/noble/aerospike-asadm/aerospike-asadm_5.0.3-5ubuntu24.04_arm64.deb'; \
        asadmSha='f7052249615977668d3608e998b51dace08b600477575e6bb90b88e23bdecaf8'; \
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
    # requirement on UBI). An absent file means the packaging changed, which is a \
    # condition that stops a release rather than annotating it: the tgz path this \
    # replaced had an unconditional cp in the same errexit chain, so a warning here \
    # would be the one place the guarantee got weaker. \
    if [ ! -f /opt/aerospike/doc/LICENSE ]; then \
        echo >&2 "error: /opt/aerospike/doc/LICENSE not found - the package no longer ships its license"; \
        exit 1; \
    fi; \
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
