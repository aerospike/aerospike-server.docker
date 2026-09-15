
#
# Aerospike Server Dockerfile
#
# https://github.com/aerospike/aerospike-server.docker
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.7

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi9/ubi-minimal:9.7" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="8.0.0.20" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="enterprise"

ENV AEROSPIKE_LINUX_BASE="registry.access.redhat.com/ubi9/ubi-minimal:9.7"

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
    # Aerospike publishes some packages (notably aerospike-asadm) with the dpkg arch \
    # spelling rather than the kernel one, so both are matched when collecting. \
    if [ "${ARCH}" = "x86_64" ]; then \
        ALT_ARCH="amd64"; \
    elif [ "${ARCH}" = "aarch64" ]; then \
        ALT_ARCH="arm64"; \
    fi; \
    # curl-minimal is preferred on ubi-minimal; fall back to full curl if absent. \
    if ! command -v curl >/dev/null 2>&1; then \
        if ! microdnf install -y curl-minimal; then \
            microdnf install -y curl; \
        fi; \
    fi; \
    if [ "${ARCH}" = "x86_64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static'; \
        tiniSha='d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940'; \
        serverUrl='https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local/el9/x86_64/aerospike-server-enterprise-8.0.0.20-15.el9.x86_64.rpm'; \
        serverSha='2a438bf95a060a854e684d1552b5b9ba4ee9f31a11bcf8bc8788aa35cf9ee534'; \
        asadmUrl='https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local/el9/x86_64/aerospike-asadm-5.0.3-5.el9.x86_64.rpm'; \
        asadmSha='acf4e3ac7cd59cc3b5fc26b0cc4dfbb0f8f7610e8a3cfb2dbe84a576a830a05d'; \
    elif [ "${ARCH}" = "aarch64" ]; then \
        tiniUrl='https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static-arm64'; \
        tiniSha='1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b'; \
        serverUrl='https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local/el9/aarch64/aerospike-server-enterprise-8.0.0.20-15.el9.aarch64.rpm'; \
        serverSha='6a93fb53d63a6330845a9912b05106ff3b4a705053cadb62859e8efd2c13f53a'; \
        asadmUrl='https://aerospike.jfrog.io/artifactory/database-rpm-prod-public-local/el9/aarch64/aerospike-asadm-5.0.3-5.el9.aarch64.rpm'; \
        asadmSha='976726c1be67bb96ffea387cf57a9e76755c23a2854239a5ef1b55bb1c1a722b'; \
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
    # Downloads are named to match the arch-qualified globs used by the install step \
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
    # Collect all arch-matching packages in /tmp/aerospike/: \
    #   - aerospike-server-*.${ARCH}.rpm  (required) \
    #   - aerospike-tools-*.${ARCH}.rpm   (optional; staged when server declares a \
    #                                      hard Requires on aerospike-tools) \
    #   - aerospike-asadm-*.${ARCH}.rpm   (optional; downloaded or staged above, \
    #                                      including arch-independent .noarch.rpm) \
    pkgs=(); \
    serverFound=false; \
    for f in /tmp/aerospike/aerospike-server-*."${ARCH}".rpm; do \
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
    # aerospike-asadm* rather than aerospike-asadm-*: the resolver accepts both \
    # separators (aerospike-asadm[-_]), so requiring the hyphen here would let a \
    # locally staged aerospike-asadm_5.0.3-....rpm be resolved, logged as included \
    # and copied in, then matched by none of these globs -- an image that ships \
    # without asadm while the generation log says it has it. The server and tools \
    # packages still cannot match: their names begin aerospike-server- / \
    # aerospike-tools-. \
    for f in /tmp/aerospike/aerospike-tools-*."${ARCH}".rpm \
        /tmp/aerospike/aerospike-asadm*."${ARCH}".rpm \
        /tmp/aerospike/aerospike-asadm*."${ALT_ARCH}".rpm \
        /tmp/aerospike/aerospike-asadm*.noarch.rpm; do \
        if [ -f "${f}" ]; then pkgs+=("${f}"); fi; \
    done; \
    rpm -i --excludedocs "${pkgs[@]}"; \
  }; \
  { \
    # Post-install housekeeping.
    mkdir -p /licenses /var/log/aerospike /var/run/aerospike; \
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
