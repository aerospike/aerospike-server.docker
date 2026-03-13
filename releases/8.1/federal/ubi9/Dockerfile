#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Federal Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi9/ubi-minimal:9.4" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.1.1.1" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="federal"

ENV AEROSPIKE_LINUX_BASE="registry.access.redhat.com/ubi9/ubi-minimal:9.4"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-federal/8.1.1.1/aerospike-server-federal_8.1.1.1_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="2f9fd1729f51ad4847f5ea8373ed7fc465f47cfb7604562b94a7427ad684d8be"
ARG AEROSPIKE_AARCH64_LINK=""
ARG AEROSPIKE_SHA_AARCH64=""

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install Aerospike Server and Tools
# hadolint ignore=DL3041
RUN \
  { \
    microdnf install -y --setopt=install_weak_deps=0 \
      findutils \
      tar \
      gzip \
      xz \
      ca-certificates \
      cpio; \
  }; \
  { \
    ARCH="$(uname -m)"; \
    if [ "${ARCH}" = "x86_64" ]; then \
      sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
      suffix=""; \
    elif [ "${ARCH}" = "aarch64" ]; then \
      sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b; \
      suffix="-arm64"; \
    else \
      echo "Unsupported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" -o /usr/bin/as-tini-static; \
    echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    ARCH="$(uname -m)"; \
    mkdir -p aerospike/pkg; \
    if [ "${ARCH}" = "x86_64" ]; then \
      pkg_link="${AEROSPIKE_X86_64_LINK}"; \
      sha256="${AEROSPIKE_SHA_X86_64}"; \
    elif [ "${ARCH}" = "aarch64" ]; then \
      pkg_link="${AEROSPIKE_AARCH64_LINK}"; \
      sha256="${AEROSPIKE_SHA_AARCH64}"; \
    else \
      echo "Unsupported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
      echo "Could not fetch pkg - ${pkg_link}" >&2; \
      exit 1; \
    fi; \
    echo "${sha256} aerospike-server.tgz" | sha256sum -c -; \
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike; \
    rm aerospike-server.tgz; \
    mkdir -p /var/{log,run}/aerospike; \
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
  }; \
  { \
    rpm -i --excludedocs aerospike/aerospike-server-*.rpm; \
    rm -rf /opt/aerospike/bin; \
  }; \
  { \
    rpm2cpio aerospike/aerospike-tools*.rpm | cpio -idmv -D aerospike/pkg; \
  }; \
  { \
    find aerospike/pkg/opt/aerospike/bin/ -user aerospike -group aerospike -exec chown root:root {} +; \
    mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike; \
    if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/; \
    else \
      mkdir /usr/lib/asadm; \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/; \
    fi; \
    ln -s /usr/lib/asadm/asadm /usr/bin/asadm; \
    if [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ]; then \
      mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/; \
    fi; \
    ln -s /usr/lib/asadm/asinfo /usr/bin/asinfo; \
  }; \
  { \
    rm -rf aerospike; \
  }; \
  { \
    microdnf remove -y findutils tar gzip xz cpio; \
    microdnf clean all; \
    rm -rf /var/cache/yum /var/cache/dnf; \
  }; \
  echo "done";

# Add the Aerospike configuration specific to this dockerfile
COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY features.conf /etc/aerospike/features.conf

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

# Tini init set to restart ASD on SIGUSR1 and terminate ASD on SIGTERM
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Execute the run script in foreground mode
CMD ["asd"]
