
#
# Aerospike Server Dockerfile
#
# https://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:24.04

LABEL org.opencontainers.image.title="Aerospike Federal Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.version="7.2.0.17" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="federal"

ENV AEROSPIKE_LINUX_BASE="ubuntu:24.04"
ARG AEROSPIKE_X86_64_LINK="https://download.aerospike.com/artifacts/aerospike-server-federal/7.2.0.17/aerospike-server-federal_7.2.0.17_tools-13.0.0_ubuntu24.04_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="c7d03805d11ff1fcec190971e6f50ef6c38c5886ac498ed7cbee1fc829279f72"
ARG AEROSPIKE_AARCH64_LINK=""
ARG AEROSPIKE_SHA_AARCH64=""
ARG AEROSPIKE_COMPAT_LIBS="1"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Aerospike tini fork (vendored under static/tini/); see static/tini/SOURCES.txt.
# COPY avoids RUN-time fetch from GitHub (Docker Official / air-gapped / reproducible builds).
# hadolint ignore=DL3042
COPY static/tini/as-tini-static-amd64 static/tini/as-tini-static-arm64 /opt/aerospike-tini/

# Install Aerospike Server and Tools
# hadolint ignore=DL3003,DL3008,DL3041,SC2015
RUN \
  { \
    # Install tini from vendored binaries.
    ARCH="$(dpkg --print-architecture)"; \
    case "${ARCH}" in \
        amd64) _tini_arch=amd64 ;; \
        arm64) _tini_arch=arm64 ;; \
        *) echo "Unsupported architecture - ${ARCH}" >&2; exit 1 ;; \
    esac; \
    cp "/opt/aerospike-tini/as-tini-static-${_tini_arch}" /usr/bin/as-tini-static; \
    chmod +x /usr/bin/as-tini-static; \
    rm -rf /opt/aerospike-tini; \
  }; \
  { \
    # Helper functions.
    # Install LDAP dependencies for enterprise/federal from the default suite only. \
    # Ubuntu 22.04: libldap-2.5-0 (sonames liblber-2.5.so.0). Ubuntu 24.04+: libldap2 only \
    # (OpenLDAP 2.6, liblber.so.2) — there is no libldap-2.5-0 package on Noble. \
    _install_ldap_deps() { \
        for cpkg in libldap-2.5-0 libldap-2.4-2 libldap2; do \
            if apt-cache show "${cpkg}" >/dev/null 2>&1; then \
                if ! apt-get install -y --no-install-recommends "${cpkg}"; then \
                    echo "Note: ${cpkg} available but not installable"; \
                fi; \
            fi; \
        done; \
        dpkg --configure -a || echo "WARNING: dpkg --configure -a reported errors (LDAP deps)" >&2; \
        if ! find /usr/lib /lib -maxdepth 2 -name 'liblber*.so*' -print -quit | grep -q .; then \
            echo "ERROR: liblber not found - libldap install failed" >&2; \
            exit 1; \
        fi; \
    }; \
    # Compat libs for tgz mode: install from current repos only. \
    _install_compat_libs_tgz() { \
        curl_pkg="libcurl4"; \
        apt-cache show libcurl4t64 >/dev/null 2>&1 && curl_pkg="libcurl4t64"; \
        for cpkg in libssl1.1 "${curl_pkg}"; do \
            if apt-cache show "${cpkg}" >/dev/null 2>&1; then \
                if ! apt-get install -y --no-install-recommends "${cpkg}"; then \
                    echo "Note: ${cpkg} available but not installable"; \
                fi; \
            fi; \
        done; \
        dpkg --configure -a || echo "WARNING: dpkg --configure -a reported errors (compat tgz)" >&2; \
    }; \
    # Native .deb path: same compat policy as tgz — no extra apt suites. \
    _install_compat_libs_native() { \
        _install_compat_libs_tgz; \
        for cpkg in libldap-2.4-2 libldap-2.5-0 libldap2; do \
            if apt-cache show "${cpkg}" >/dev/null 2>&1; then \
                if ! apt-get install -y --no-install-recommends "${cpkg}"; then \
                    echo "Note: ${cpkg} available but not installable"; \
                fi; \
            fi; \
        done; \
        dpkg --configure -a || echo "WARNING: dpkg --configure -a reported errors (compat native)" >&2; \
        ldconfig || echo "WARNING: ldconfig failed" >&2; \
    }; \
    # Install tools from extracted tgz (tools .deb -> ar -> tar -> move binaries). \
    # Gracefully skips asadm/asinfo symlinks when the binary is absent so that \
    # server-only packages (no tools) do not produce dangling symlinks. \
    _install_tools_from_tgz() { \
        ar -x aerospike/aerospike-tools*.deb --output aerospike/pkg; \
        tar xf aerospike/pkg/data.tar.xz -C aerospike/pkg/; \
        find aerospike/pkg/opt/aerospike/bin/ -exec chown root:root {} +; \
        if [ -f aerospike/pkg/etc/aerospike/astools.conf ]; then \
            mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike; \
        fi; \
        if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then \
            mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/; \
        elif [ -e 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then \
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
  }; \
  { \
    # Main install logic.
    export DEBIAN_FRONTEND=noninteractive; \
    ARCH="$(dpkg --print-architecture)"; \
    # Install build dependencies (procps provides /usr/bin/ps; kept in the final image — see purge loop) \
    apt-get update -y; \
    if [ "${ARCH}" = "arm64" ]; then \
        _try=1; \
        while [ "${_try}" -le 3 ]; do \
            if apt-get install -y --no-install-recommends \
                binutils xz-utils ca-certificates curl procps; then \
                break; \
            fi; \
            dpkg --configure -a || echo "WARNING: dpkg --configure -a (before retry apt install)" >&2; \
            sleep 2; \
            _try=$((_try + 1)); \
        done; \
        if [ "${_try}" -gt 3 ]; then \
            echo "ERROR: apt-get install build dependencies failed after retries" >&2; \
            exit 1; \
        fi; \
    else \
        apt-get install -y --no-install-recommends \
            binutils xz-utils ca-certificates curl procps; \
    fi; \
    command -v curl >/dev/null 2>&1 || { \
        echo "ERROR: curl not found" >&2; \
        exit 1; \
    }; \
    # Select arch-specific package link and SHA \
    if [ "${ARCH}" = "amd64" ]; then \
        pkg_link="${AEROSPIKE_X86_64_LINK:-}"; \
        sha256="${AEROSPIKE_SHA_X86_64:-}"; \
    else \
        pkg_link="${AEROSPIKE_AARCH64_LINK:-}"; \
        sha256="${AEROSPIKE_SHA_AARCH64:-}"; \
    fi; \
    # --- Install: local native .deb (AEROSPIKE_LOCAL_PKG=1) --- \
    if [ "${AEROSPIKE_LOCAL_PKG:-0}" = "1" ]; then \
        if [ "${ARCH}" = "amd64" ]; then \
            cp /tmp/server_amd64.deb server.deb; \
            if [ -f /tmp/server_amd64.deb.sha256 ]; then \
                pkg_hash=$(awk '{print $1}' /tmp/server_amd64.deb.sha256); \
                echo "${pkg_hash}  server.deb" | sha256sum -c -; \
            fi; \
        else \
            cp /tmp/server_arm64.deb server.deb; \
            if [ -f /tmp/server_arm64.deb.sha256 ]; then \
                pkg_hash=$(awk '{print $1}' /tmp/server_arm64.deb.sha256); \
                echo "${pkg_hash}  server.deb" | sha256sum -c -; \
            fi; \
        fi; \
        if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
            _install_ldap_deps; \
        fi; \
        if [ "${AEROSPIKE_COMPAT_LIBS:-0}" = "1" ]; then \
            _install_compat_libs_native; \
        fi; \
        if [ "${ARCH}" = "arm64" ]; then \
            if ! dpkg -i server.deb; then \
                dpkg --configure -a || echo "WARNING: dpkg --configure -a before server.deb retry" >&2; \
                sleep 2; \
                dpkg -i server.deb || { \
                    echo "ERROR: dpkg -i server.deb failed" >&2; \
                    exit 1; \
                }; \
            fi; \
            dpkg --configure -a || echo "WARNING: dpkg --configure -a after server.deb" >&2; \
        else \
            dpkg -i server.deb; \
        fi; \
        command -v asd >/dev/null 2>&1 || { \
            echo "ERROR: asd not installed" >&2; \
            exit 1; \
        }; \
        mkdir -p /var/{log,run}/aerospike; \
        rm -f server.deb; \
        if ! dpkg --purge curl; then \
            echo "Note: keeping curl (has reverse dependencies)"; \
        fi; \
        apt-get autoremove -y || echo "WARNING: apt-get autoremove failed" >&2; \
        rm -rf /var/lib/apt/lists/*; \
    # --- Install: tgz bundle (default) --- \
    else \
        mkdir -p aerospike/pkg; \
        if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o aerospike-server.tgz; then \
            sleep 5; \
            if ! curl -fsSL --retry 3 --retry-delay 3 "${pkg_link}" -o aerospike-server.tgz; then \
                echo "Could not fetch pkg - ${pkg_link}" >&2; \
                exit 1; \
            fi; \
        fi; \
        echo "${sha256} aerospike-server.tgz" | sha256sum -c -; \
        tar xzf aerospike-server.tgz --strip-components=1 -C aerospike; \
        rm aerospike-server.tgz; \
        mkdir -p /var/{log,run}/aerospike /etc/aerospike /licenses; \
        cp aerospike/LICENSE /licenses; \
        if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
            if [ -f aerospike/features.conf ]; then \
                cp aerospike/features.conf /etc/aerospike/features.conf; \
            elif [ -f aerospike/etc/aerospike/features.conf ]; then \
                cp aerospike/etc/aerospike/features.conf /etc/aerospike/features.conf; \
            fi; \
        fi; \
        if [ "${AEROSPIKE_EDITION}" = "enterprise" ] || [ "${AEROSPIKE_EDITION}" = "federal" ]; then \
            _install_ldap_deps; \
        fi; \
        if [ "${AEROSPIKE_COMPAT_LIBS:-0}" = "1" ]; then \
            _install_compat_libs_tgz; \
        fi; \
        if [ "${ARCH}" = "arm64" ]; then \
            if ! dpkg -i aerospike/aerospike-server-*.deb; then \
                dpkg --configure -a || echo "WARNING: dpkg --configure -a before server deb retry" >&2; \
                sleep 2; \
                dpkg -i aerospike/aerospike-server-*.deb || { \
                    echo "ERROR: dpkg -i aerospike-server deb failed" >&2; \
                    exit 1; \
                }; \
            fi; \
            dpkg --configure -a || echo "WARNING: dpkg --configure -a after server deb" >&2; \
        else \
            dpkg -i aerospike/aerospike-server-*.deb; \
        fi; \
        command -v asd >/dev/null 2>&1 || { \
            echo "ERROR: asd not installed" >&2; \
            exit 1; \
        }; \
        rm -rf /opt/aerospike/bin; \
        _install_tools_from_tgz; \
        rm -rf aerospike; \
        for pkg in binutils xz-utils curl; do \
            if ! dpkg --purge "${pkg}"; then \
                echo "Note: keeping ${pkg} (has reverse dependencies)"; \
            fi; \
        done; \
        apt-get autoremove -y || echo "WARNING: apt-get autoremove failed" >&2; \
        rm -rf /var/lib/apt/lists/*; \
    fi; \
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
