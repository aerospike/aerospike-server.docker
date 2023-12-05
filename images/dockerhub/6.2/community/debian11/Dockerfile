
#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM docker.io/debian:bullseye-slim

ARG AEROSPIKE_X86_64_LINK="https://artifacts.aerospike.com/aerospike-server-community/6.2.0.22/aerospike-server-community_6.2.0.22_tools-8.1.0_debian11_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="83aa5471af5d541be72156dbad4eec6e4bd955e84c8731cc8ec49ae7f7eebd7f"
ARG AEROSPIKE_AARCH64_LINK="https://artifacts.aerospike.com/aerospike-server-community/6.2.0.22/aerospike-server-community_6.2.0.22_tools-8.1.0_debian11_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="5ac063000736e043445b0b95b371ff8493b3d6814319124afe918ccd4e3a153b"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install Aerospike Server and Tools
RUN \
  { \
    # 00-prelude-deb.part - Setup dependencies for scripts.
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends apt-utils; \
    apt-get install -y --no-install-recommends \
      binutils \
      ca-certificates \
      curl \
      file \
      xz-utils; \
  }; \
  { \
    # 00-prelude-deb.part - Install procps for tests.
    apt-get install -y --no-install-recommends procps; \
  }; \
  { \
    # 10-download.part - Vars used for tini and tools.
    VERSION="$(grep -oE "/[0-9]+[.][0-9]+[.][0-9]+([.][0-9]+)+(-rc[0-9]+)*/" <<<"${AEROSPIKE_X86_64_LINK}" | tr -d '/')"; \
  }; \
  { \
    # 10-common.part - Install tini.
    ARCH="$(file -Lb /usr/bin/awk | awk -F'[,]*' '{ print $2 }' | awk '{ print $NF }')"; \
    if [ "${ARCH}" = "x86-64" ]; then \
      sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
      suffix=""; \
    elif [ "${ARCH}" = "aarch64" ]; then \
      sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b; \
      suffix="-arm64"; \
    else \
      echo "Unsuported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    curl -fsSL "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" --output /usr/bin/as-tini-static; \
    echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -; \
    chmod +x /usr/bin/as-tini-static; \
  }; \
  { \
    # 10-download.part - Download server and tools.
    ARCH="$(file -Lb /usr/bin/awk | awk -F'[,]*' '{ print $2 }' | awk '{ print $NF }')"; \
    mkdir -p aerospike/pkg; \
    if [ "${ARCH}" = "x86-64" ]; then \
      pkg_link="${AEROSPIKE_X86_64_LINK}"; \
      sha256="${AEROSPIKE_SHA_X86_64}"; \
    elif [ "${ARCH}" = "aarch64" ]; then \
      pkg_link="${AEROSPIKE_AARCH64_LINK}"; \
      sha256="${AEROSPIKE_SHA_AARCH64}"; \
    else \
      echo "Unsuported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi; \
    if ! curl -fsSL "${pkg_link}" --output aerospike-server.tgz; then \
      echo "Could not fetch pkg - ${pkg_link}" >&2; \
      exit 1; \
    fi; \
    echo "${sha256} aerospike-server.tgz" | sha256sum -c -; \
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike; \
    rm -f aerospike-server.tgz; \
    # These directories are required for backward compatibility.
    mkdir -p /var/{log,run}/aerospike; \
    # Copy license file to standard location.
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
  }; \
  { \
    # 20-install-dependencies-deb.part - Install server and dependencies.
    apt-get install -y --no-install-recommends \
      # required for EE and pre 6.0
      libcurl4 \
      # required for EE
      libldap-2.4.2; \
    dpkg -i aerospike/aerospike-server-*.deb; \
    rm -rf /opt/aerospike/bin; \
  }; \
  { \
    # 20-install-dependencies-deb.part - Install tools dependencies.
    if ! [ "$(printf "%s\n%s" "${VERSION}" "6.2.0.3" | sort -V | head -1)" != "${VERSION}" ]; then \
      # Tools before 6.0 need python3.
      apt-get install -y --no-install-recommends \
        python3 \
        python3-distutils; \
    fi; \
    # Tools after 6.0 bundled their own python interpreter.
  }; \
  { \
    # 20-install-dependencies-deb.part - Extract tools.
    # ar on debian10 doesn't support '--output'
    pushd aerospike/pkg || exit 1; \
    ar -x ../aerospike-tools*.deb; \
    popd || exit 1; \
    tar xf aerospike/pkg/data.tar.xz -C aerospike/pkg/; \
  }; \
  { \
    # 30-install-tools.part - install asinfo and asadm.
    find aerospike/pkg/opt/aerospike/bin/ -user aerospike -group aerospike -exec chown root:root {} + || true; \
    mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike; \
    if ! [ "$(printf "%s\n%s" "${VERSION}" "6.2" | sort -V | head -1)" != "${VERSION}" ]; then \
       mv aerospike/pkg/opt/aerospike/bin/aql /usr/bin; \
    fi; \
    if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then \
      # Since tools release 7.0.5, asadm has been moved from
      # /opt/aerospike/bin/asadm to /opt/aerospike/bin/asadm/asadm
      # (inside an asadm directory).
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/; \
    else \
      mkdir /usr/lib/asadm; \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/; \
    fi; \
    ln -s /usr/lib/asadm/asadm /usr/bin/asadm; \
    if [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ]; then \
      # Since tools release 7.1.1, asinfo has been moved from
      # /opt/aerospike/bin/asinfo to /opt/aerospike/bin/asadm/asinfo
      # (inside an asadm directory).
      mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/; \
    fi; \
    ln -s /usr/lib/asadm/asinfo /usr/bin/asinfo; \
  }; \
  { \
    # 40-cleanup.part - remove extracted aerospike pkg directory.
    rm -rf aerospike; \
  }; \
  { \
    # 50-remove-prelude-deb.part - Remove dependencies for scripts.
    rm -rf /var/lib/apt/lists/*; \
    dpkg --purge \
      apt-utils \
      binutils \
      ca-certificates \
      curl \
      file \
      xz-utils 2>&1; \
    apt-get purge -y; \
    apt-get autoremove -y; \
    unset DEBIAN_FRONTEND; \
  }; \
  echo "done";

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/debian:bullseye-slim" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="6.2.0.22" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

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

RUN chown aerospike:aerospike /etc/aerospike/*
USER aerospike:aerospike

COPY entrypoint.sh /entrypoint.sh

# Tini init set to restart ASD on SIGUSR1 and terminate ASD on SIGTERM
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Execute the run script in foreground mode
CMD ["asd"]
