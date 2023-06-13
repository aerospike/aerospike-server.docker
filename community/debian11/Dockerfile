
#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM debian:bullseye-slim

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="community"

ARG AEROSPIKE_X86_64_LINK="https://artifacts.aerospike.com/aerospike-server-community/6.3.0.5/aerospike-server-community_6.3.0.5_tools-8.4.0_debian11_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="f294a6e4f9e009c90c23931bb2499bcf50685262de9576c2fb60c654c369a702"
ARG AEROSPIKE_AARCH64_LINK="https://artifacts.aerospike.com/aerospike-server-community/6.3.0.5/aerospike-server-community_6.3.0.5_tools-8.4.0_debian11_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="fa5670022725f30f2a37e17881104a91c2969a84b1789426b3e8c64b5081eb8a"

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
    ARCH="$(dpkg --print-architecture)"; \
    if [ "${ARCH}" = "amd64" ]; then \
      sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
      suffix=""; \
    elif [ "${ARCH}" = "arm64" ]; then \
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
    ARCH="$(dpkg --print-architecture)"; \
    mkdir -p aerospike/pkg; \
    if [ "${ARCH}" = "amd64" ]; then \
      pkg_link="${AEROSPIKE_X86_64_LINK}"; \
      sha256="${AEROSPIKE_SHA_X86_64}"; \
    elif [ "${ARCH}" = "arm64" ]; then \
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
    rm aerospike-server.tgz; \
    # These directories are required for backward compatibility.
    mkdir -p /var/{log,run}/aerospike; \
    # Copy license file to standard location.
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
  }; \
  { \
    # 20-install-dependencies-deb.part - Install server and dependencies.
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ]; then \
      apt-get install -y --no-install-recommends \
        libcurl4 \
        libldap-2.4.2; \
    elif ! [ "$(printf "%s\n%s" "${VERSION}" "6.0" | sort -V | head -1)" != "${VERSION}" ]; then \
      apt-get install -y --no-install-recommends \
        libcurl4; \
    fi; \
    dpkg -i aerospike/aerospike-server-*.deb; \
    rm -rf /opt/aerospike/bin; \
  }; \
  { \
    # 20-install-dependencies-deb.part - Install tools dependencies.
    if ! [ "$(printf "%s\n%s" "${VERSION}" "5.1" | sort -V | head -1)" != "${VERSION}" ]; then \
      # Tools before 5.1 need python2.
      apt-get install -y --no-install-recommends \
        python2; \
    elif ! [ "$(printf "%s\n%s" "${VERSION}" "6.2.0.3" | sort -V | head -1)" != "${VERSION}" ]; then \
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
    find aerospike/pkg/opt/aerospike/bin/ -user aerospike -group aerospike -exec chown root:root {} +; \
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
      xz-utils 2>&1; \
    apt-get purge -y; \
    apt-get autoremove -y; \
    unset DEBIAN_FRONTEND; \
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

# Tini init set to restart ASD on SIGUSR1 and terminate ASD on SIGTERM
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Execute the run script in foreground mode
CMD ["asd"]
