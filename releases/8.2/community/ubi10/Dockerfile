
#
# Aerospike Server Dockerfile
#
# https://github.com/aerospike/aerospike-server.docker
#

FROM registry.access.redhat.com/ubi10/ubi-minimal:10.0

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi10/ubi-minimal:10.0" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.2.0.0" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="community"

ENV AEROSPIKE_LINUX_BASE="registry.access.redhat.com/ubi10/ubi-minimal:10.0"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# hadolint ignore=DL3041
RUN \
  set -eux; \
  microdnf install -y --setopt=install_weak_deps=0 \
    ca-certificates \
    procps-ng \
  ; \
  microdnf clean all; \
  rm -rf /var/cache/yum /var/cache/dnf

# Install Aerospike Server and Tools
# hadolint ignore=DL3003,DL3008,DL3041,SC2015
RUN \
  set -eux; \
  { \
    # Install curl and resolve arch-specific links.
    ARCH="$(rpm --eval '%{_arch}')"; \
    # curl-minimal is preferred on ubi-minimal; fall back to full curl if absent. \
    if ! command -v curl >/dev/null 2>&1; then \
        if ! microdnf install -y curl-minimal; then \
            microdnf install -y curl; \
        fi; \
    fi; \
    if [ "${ARCH}" = "x86_64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static'; \
        tiniSha='d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940'; \
        serverUrl='https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local/el10/x86_64/aerospike-server-community-8.2.0.0-12.el10.x86_64.rpm'; \
        serverSha='e0492d01808a482bac87879c74caf9729ba272249016835210f1d205249c1214'; \
        asadmUrl='https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local/el10/x86_64/aerospike-asadm-5.1.0-2.el10.x86_64.rpm'; \
        asadmSha='26f3ba9755f47c0110a6cd06f6dfc7c56d6348389d6eb124d51ba4ec3d9a32d6'; \
    elif [ "${ARCH}" = "aarch64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'; \
        tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'; \
        serverUrl='https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local/el10/aarch64/aerospike-server-community-8.2.0.0-12.el10.aarch64.rpm'; \
        serverSha='4355a41e1344552adaa0b9aa269505e4ea53acc7a2122f198a5742e3a7a2aa6f'; \
        asadmUrl='https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local/el10/aarch64/aerospike-asadm-5.1.0-2.el10.aarch64.rpm'; \
        asadmSha='e9f1d814f49341d62a2b613aafba9e8e9ba5110ac354e63e58e51dff0d5e7bb2'; \
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
    # shadow-utils: provides groupadd/useradd used by aerospike-server %post scriptlet. \
    # findutils: provides find(1) used by aerospike-server %post scriptlet. \
    # Downloads are named to match the arch-qualified glob used by the install step \
    # below, so remote and pre-staged packages are collected the same way. \
    microdnf install -y --setopt=install_weak_deps=0 findutils shadow-utils; \
    mkdir -p /tmp/aerospike; \
    if [ -n "${serverUrl}" ]; then \
        curl -fL -o "/tmp/aerospike/aerospike-server-dl.${ARCH}.rpm" "${serverUrl}"; \
        echo "${serverSha} */tmp/aerospike/aerospike-server-dl.${ARCH}.rpm" | sha256sum --strict --check -; \
    fi; \
    if [ -n "${asadmUrl}" ]; then \
        curl -fL -o "/tmp/aerospike/aerospike-asadm-dl.${ARCH}.rpm" "${asadmUrl}"; \
        echo "${asadmSha} */tmp/aerospike/aerospike-asadm-dl.${ARCH}.rpm" | sha256sum --strict --check -; \
    fi; \
  }; \
  { \
    # Install Aerospike server.
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
        microdnf install -y --setopt=install_weak_deps=0 openldap; \
    fi; \
    # Arch-qualified because a local build stages both arches through one COPY. \
    rpm -i --excludedocs /tmp/aerospike/aerospike-*."${ARCH}".rpm; \
  }; \
  { \
    # Post-install housekeeping.
    mkdir -p /licenses /var/log/aerospike /var/run/aerospike; \
    # /licenses/ is where Red Hat certification expects the license to be. \
    cp /opt/aerospike/doc/LICENSE /licenses/; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
        if [ -f /tmp/aerospike/features.conf ]; then \
            mkdir -p /etc/aerospike; \
            cp /tmp/aerospike/features.conf /etc/aerospike/features.conf; \
        fi; \
    fi; \
    rm -rf /tmp/aerospike; \
    microdnf clean all; \
    rm -rf /var/cache/yum /var/cache/dnf; \
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
