#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7

LABEL org.opencontainers.image.title="Aerospike Community Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi9/ubi-minimal:9.7" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="7.2.0.16" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="community"

ENV AEROSPIKE_LINUX_BASE="registry.access.redhat.com/ubi9/ubi-minimal:9.7"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.2.0.16/aerospike-server-community_7.2.0.16_tools-12.1.1_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="c1199ad51aec44b9740176f6ea2edcdd0effd9b080a57a325afdd1a4f99f0295"
ARG AEROSPIKE_AARCH64_LINK="https://download.aerospike.com/artifacts/aerospike-server-community/7.2.0.16/aerospike-server-community_7.2.0.16_tools-12.1.1_el9_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="bb8618d6526ea76edffa9696dedd6caff87d3b635f93a0609b978af5737f33b9"
ARG AEROSPIKE_COMPAT_LIBS="0"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install Aerospike Server and Tools
# hadolint ignore=DL3041
RUN \
  _retry() { local _i; for _i in 1 2 3 4 5; do if "$@"; then return 0; fi; sleep $((_i*5)); done; "$@"; }; \
  { \
    _retry microdnf install -y --setopt=install_weak_deps=0 \
      findutils \
      tar \
      gzip \
      xz \
      ca-certificates \
      cpio \
      shadow-utils; \
  }; \
  { \
    if ! command -v curl >/dev/null 2>&1; then \
      if ! microdnf install -y curl-minimal; then \
        microdnf install -y curl; \
      fi; \
    fi; \
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found" >&2; exit 1; }; \
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
    if ! curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" -o /usr/bin/as-tini-static; then \
      sleep 5; \
      curl -fsSL --retry 3 --retry-delay 3 "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" -o /usr/bin/as-tini-static; \
    fi; \
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
      sleep 5; \
      if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" --output aerospike-server.tgz; then \
        echo "Could not fetch pkg - ${pkg_link}" >&2; \
        exit 1; \
      fi; \
    fi; \
    echo "${sha256} aerospike-server.tgz" | sha256sum -c -; \
    tar xzf aerospike-server.tgz --strip-components=1 -C aerospike; \
    rm aerospike-server.tgz; \
    mkdir -p /var/{log,run}/aerospike; \
    mkdir -p /licenses; \
    cp aerospike/LICENSE /licenses; \
  }; \
  { \
    ARCH="$(uname -m)"; \
    if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
      _retry microdnf install -y --setopt=install_weak_deps=0 openldap; \
    fi; \
    if ! rpm -i --excludedocs aerospike/aerospike-server-*.rpm; then \
      sleep 3; \
      if ! rpm -i --force --excludedocs aerospike/aerospike-server-*.rpm; then \
        sleep 5; \
        rpm -i --force --nodeps --excludedocs aerospike/aerospike-server-*.rpm; \
      fi; \
    fi; \
    command -v asd >/dev/null 2>&1 || { echo "ERROR: asd not installed" >&2; exit 1; }; \
    rm -rf /opt/aerospike/bin; \
  }; \
  { \
    shopt -s nullglob; \
    _tool_rpms=(aerospike/aerospike-tools*.rpm); \
    if [ "${#_tool_rpms[@]}" -eq 0 ]; then \
      echo "ERROR: no aerospike-tools*.rpm under aerospike/ after tar extract (cwd=$(pwd))" >&2; \
      if ! ls -la aerospike >&2; then true; fi; \
      exit 1; \
    fi; \
    _tool_rpm_base="${_tool_rpms[0]##*/}"; \
    if ! rpm2cpio "aerospike/${_tool_rpm_base}" | cpio -idm -D aerospike/pkg; then \
      sleep 3; \
      rpm2cpio "aerospike/${_tool_rpm_base}" | cpio -idm -D aerospike/pkg; \
    fi; \
  }; \
  { \
    if [ -d aerospike/pkg/opt/aerospike/bin/ ]; then \
      find aerospike/pkg/opt/aerospike/bin/ -exec chown root:root {} +; \
    fi; \
    mkdir -p /etc/aerospike; \
    if [ -f aerospike/pkg/etc/aerospike/astools.conf ]; then \
      mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike/; \
    fi; \
    if [ ! -e aerospike/pkg/opt/aerospike/bin/asadm ]; then \
      echo "ERROR: asadm missing under aerospike/pkg/opt/aerospike/bin after tools extract" >&2; \
      find aerospike/pkg -maxdepth 6 \( -name asadm -o -name asinfo \) -print >&2; \
      exit 1; \
    fi; \
    if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/; \
    else \
      mkdir -p /usr/lib/asadm; \
      mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/; \
    fi; \
    if [ -e /usr/lib/asadm/asadm ]; then \
      ln -snf /usr/lib/asadm/asadm /usr/bin/asadm; \
    fi; \
    if [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ]; then \
      mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/; \
    fi; \
    if [ -e /usr/lib/asadm/asinfo ]; then \
      ln -snf /usr/lib/asadm/asinfo /usr/bin/asinfo; \
    fi; \
  }; \
  { \
    rm -rf aerospike; \
  }; \
  { \
    if ! microdnf remove -y findutils tar gzip xz cpio; then true; fi; \
    if ! microdnf clean all; then true; fi; \
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

# Tini init set to restart ASD on SIGUSR1 and terminate ASD on SIGTERM
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Execute the run script in foreground mode
CMD ["asd"]
