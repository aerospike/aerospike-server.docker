
#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM redhat/ubi8-minimal

ARG AEROSPIKE_X86_64_LINK="https://artifacts.aerospike.com/aerospike-server-enterprise/5.7.0.31/aerospike-server-enterprise-5.7.0.31-el8.tgz"
ARG AEROSPIKE_SHA_X86_64="42f618126aff48735eb589c0306b8bdba5ba151d09892479e702e1993077672a"
ARG AEROSPIKE_AARCH64_LINK=""
ARG AEROSPIKE_SHA_AARCH64=""

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install Aerospike Server and Tools
RUN \
  { \
    # 00-prelude-rpm.part - Setup dependencies for scripts.
    microdnf update -y; \
    microdnf install -y \
      binutils \
      file \
      findutils \
      gzip \
      shadow-utils \
      tar \
      xz; \
  }; \
  { \
    # 00-prelude-rpm.part - Install procps for tests.
    microdnf install -y procps-ng; \
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
    # 20-install-dependencies-rpm.part - Install server and dependencies.
    rpm -i aerospike/aerospike-server-*.rpm; \
    rm -rf /opt/aerospike/bin; \
  }; \
  { \
    # 20-install-dependencies-rpm.part - Install tools dependencies.
    if ! [ "$(printf "%s\n%s" "${VERSION}" "6.2.0.3" | sort -V | head -1)" != "${VERSION}" ]; then \
      # Tools before 6.0 need python3.
      microdnf install -y python3; \
    fi; \
    # Tools after 6.0 bundled their own python interpreter.
  }; \
  { \
    # 20-install-dependencies-rpm.part - Extract tools.
    pushd aerospike/pkg || exit 1; \
    rpm2archive -n ../aerospike-tools*.rpm; \
    tar xf ../aerospike-tools*.tar -C .; \
    rm -f ../aerospike-tools*.tar; \
    popd || exit 1; \
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
    # 50-remove-prelude-rpm.part - Remove dependencies for scripts.
    microdnf remove -y \
      # binutils - dependency issues on ubi9
      file \
      findutils \
      # gzip - dependency issues on ubi9
      shadow-utils \
      tar \
      xz 2>&1; \
    microdnf clean all; \
  }; \
  echo "done";

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/redhat/ubi8-minimal" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="5.7.0.31" \
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
