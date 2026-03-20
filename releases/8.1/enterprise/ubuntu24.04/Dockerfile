#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.1.1.2" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="enterprise"

ENV AEROSPIKE_LINUX_BASE="ubuntu:24.04"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.1.1.2/aerospike-server-enterprise_8.1.1.2_tools-12.1.1_ubuntu24.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="6e66c634988291bbf0aae6413c0a05d42a89f29faf57a0b206c5e88c7a273f38"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-enterprise/8.1.1.2/aerospike-server-enterprise_8.1.1.2_tools-12.1.1_ubuntu24.04_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="cee61263b88fa2181b9bbcdb9f42a06801a071ad686dec3a9fc808aab4842362"
ARG AEROSPIKE_COMPAT_LIBS="0"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install Aerospike Server and Tools
RUN \
  { \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -y || true; \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
      apt-get install -y --no-install-recommends \
        apt-utils binutils xz-utils ca-certificates curl procps || true; \
      dpkg --configure -a || true; \
      sleep 2; \
      dpkg --configure -a || true; \
    else \
      apt-get install -y --no-install-recommends apt-utils || true; \
      apt-get install -y --no-install-recommends \
        binutils xz-utils ca-certificates curl procps; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
  }; \
  { \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "${ARCH}" = "amd64" ]; then \
      sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
      suffix=""; \
    elif [ "${ARCH}" = "arm64" ]; then \
      sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b; \
      suffix="-arm64"; \
    else \
      echo "Unsupported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" --output /usr/bin/as-tini-static; \
    echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    ARCH="$(dpkg --print-architecture)"; \
    mkdir -p aerospike/pkg; \
    if [ "${ARCH}" = "amd64" ]; then \
      pkg_link="${AEROSPIKE_X86_64_LINK}"; \
      sha256="${AEROSPIKE_SHA_X86_64}"; \
    elif [ "${ARCH}" = "arm64" ]; then \
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
    mkdir -p /etc/aerospike; \
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      if [ -f aerospike/features.conf ]; then \
        cp aerospike/features.conf /etc/aerospike/features.conf; \
      elif [ -f aerospike/etc/aerospike/features.conf ]; then \
        cp aerospike/etc/aerospike/features.conf /etc/aerospike/features.conf; \
      fi; \
    fi; \
  }; \
  { \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      apt-get install -y --no-install-recommends \
        libldap-2.5-0 || true; \
      dpkg --configure -a || true; \
      ls /usr/lib/*/liblber-2.5.so.0 >/dev/null 2>&1 || { echo "ERROR: liblber-2.5.so.0 not found – libldap-2.5-0 install failed" >&2; exit 1; }; \
    fi; \
    if [ "${AEROSPIKE_COMPAT_LIBS}" = "1" ]; then \
      curl_pkg="libcurl4"; \
      apt-cache show libcurl4t64 >/dev/null 2>&1 && curl_pkg="libcurl4t64"; \
      apt-get install -y --no-install-recommends \
        libssl1.1 "${curl_pkg}" || true; \
      dpkg --configure -a || true; \
    fi; \
    if [ "$(dpkg --print-architecture)" = "arm64" ]; then \
      dpkg -i aerospike/aerospike-server-*.deb || true; \
      dpkg --configure -a || true; \
      sleep 2; \
      dpkg --configure -a || true; \
    else \
      dpkg -i aerospike/aerospike-server-*.deb; \
    fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; dpkg -l 'aerospike*' 2>&1 || true; exit 1; }; \
    rm -rf /opt/aerospike/bin; \
  }; \
  { \
    ar -x aerospike/aerospike-tools*.deb --output aerospike/pkg; \
    tar xf aerospike/pkg/data.tar.xz -C aerospike/pkg/; \
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
    rm -rf /var/lib/apt/lists/*; \
    dpkg --purge \
      apt-utils \
      binutils \
      xz-utils 2>&1 || true; \
    apt-get purge -y curl procps || true; \
    apt-get autoremove -y || true; \
    unset DEBIAN_FRONTEND; \
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
