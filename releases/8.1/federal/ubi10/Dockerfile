
#
# Aerospike Server Dockerfile
#
# https://github.com/aerospike/aerospike-server.docker
#

FROM registry.access.redhat.com/ubi10/ubi-minimal:10.0

LABEL org.opencontainers.image.title="Aerospike Federal Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi10/ubi-minimal:10.0" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.1.2.0" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="federal"

ENV AEROSPIKE_LINUX_BASE="registry.access.redhat.com/ubi10/ubi-minimal:10.0"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# hadolint ignore=DL3041
RUN \
  microdnf install -y --setopt=install_weak_deps=0 \
    ca-certificates \
    procps-ng \
  ; \
  microdnf clean all; \
  rm -rf /var/cache/yum /var/cache/dnf

# Install Aerospike Server and Tools
# hadolint ignore=DL3003,DL3008,DL3041,SC2015
RUN \
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
        pkgLink='https://download.aerospike.com/artifacts/aerospike-server-federal/8.1.2.0/aerospike-server-federal_8.1.2.0_tools-13.0.0_el10_x86_64.tgz'; \
        pkgSha='5f49973b4257fe40d13a8fbfa8b141b2774a317585fedf949b014429c16c45d8'; \
    elif [ "${ARCH}" = "aarch64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'; \
        tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'; \
        pkgLink=''; \
        pkgSha=''; \
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
    # findutils: needed by aerospike-server %post scriptlets that invoke find(1). \
    # shadow-utils: needed by rpm %pre/%post for useradd/groupadd. \
    # tar/gzip/xz/cpio: package extraction; removed after install. \
    microdnf install -y --setopt=install_weak_deps=0 findutils tar gzip xz cpio shadow-utils; \
    mkdir -p /tmp/aerospike/pkg; \
    curl -fL -o /tmp/aerospike/pkg.tgz "${pkgLink}"; \
    echo "${pkgSha}  /tmp/aerospike/pkg.tgz" | sha256sum --check -; \
    tar -xzf /tmp/aerospike/pkg.tgz --strip-components=1 -C /tmp/aerospike; \
    rm /tmp/aerospike/pkg.tgz; \
  }; \
  { \
    # Install Aerospike server.
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
        microdnf install -y --setopt=install_weak_deps=0 openldap; \
    fi; \
    rpm -i --excludedocs /tmp/aerospike/aerospike-server-*.rpm; \
    rm -rf /opt/aerospike/bin; \
  }; \
  { \
    # Install tools.
    rpm2cpio /tmp/aerospike/aerospike-tools*.rpm | cpio -idm -D /tmp/aerospike/pkg; \
    if [ -d /tmp/aerospike/pkg/opt/aerospike/bin/ ]; then \
        find /tmp/aerospike/pkg/opt/aerospike/bin/ -exec chown root:root {} +; \
    fi; \
    mkdir -p /etc/aerospike; \
    if [ -f /tmp/aerospike/pkg/etc/aerospike/astools.conf ]; then \
        mv /tmp/aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike/; \
    fi; \
    if [ -d '/tmp/aerospike/pkg/opt/aerospike/bin/asadm' ]; then \
        mv /tmp/aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/; \
    else \
        mkdir -p /usr/lib/asadm; \
        mv /tmp/aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/; \
    fi; \
    if [ -e /usr/lib/asadm/asadm ]; then \
        ln -snf /usr/lib/asadm/asadm /usr/bin/asadm; \
    fi; \
    if [ -f '/tmp/aerospike/pkg/opt/aerospike/bin/asinfo' ]; then \
        mv /tmp/aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/; \
    fi; \
    if [ -e /usr/lib/asadm/asinfo ]; then \
        ln -snf /usr/lib/asadm/asinfo /usr/bin/asinfo; \
    fi; \
  }; \
  { \
    # Post-install housekeeping.
    mkdir -p /licenses /var/log/aerospike /var/run/aerospike; \
    cp /tmp/aerospike/LICENSE /licenses/; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
        if [ -f /tmp/aerospike/features.conf ]; then \
            cp /tmp/aerospike/features.conf /etc/aerospike/features.conf; \
        fi; \
    fi; \
    rm -rf /tmp/aerospike; \
    # Remove build-only tools; some may have reverse deps — treat as best-effort. \
    microdnf remove -y findutils tar gzip xz cpio 2>/dev/null || :; \
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
