#
# Aerospike Server Dockerfile
# Version: 8.1.1.0-start-16-gea126d3 | Edition: enterprise | Base: ubi9
#

FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4

LABEL org.opencontainers.image.title="Aerospike Enterprise Server" \
      org.opencontainers.image.version="8.1.1.0-start-16-gea126d3" \
      org.opencontainers.image.vendor="Aerospike"

ARG AEROSPIKE_EDITION="enterprise"
ARG AEROSPIKE_X86_64_LINK="https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise/8.1.1.0-start-16-gea126d3/aerospike-server-enterprise_8.1.1.0-start-16-gea126d3_tools-12.0.2_el9_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64="c95f461ff31cc0066546f6ca546b25812a247202d1505ec12cf0b1dd3293613b"
ARG AEROSPIKE_AARCH64_LINK="https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise/8.1.1.0-start-16-gea126d3/aerospike-server-enterprise_8.1.1.0-start-16-gea126d3_tools-12.0.2_el9_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64="abf2f991ebccf6330c5467324af59ba40e0af814a5c1a23b2d5322c64e08b726"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

RUN \
  # Install dependencies (curl-minimal is pre-installed in ubi-minimal)
  microdnf install -y findutils tar gzip xz ca-certificates procps-ng cpio; \
  \
  # Download tini
  ARCH="$(uname -m)"; \
  if [ "${ARCH}" = "x86_64" ]; then \
    sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
    suffix=""; \
  else \
    sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b; \
    suffix="-arm64"; \
  fi; \
  curl -fsSL "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" -o /usr/bin/as-tini-static; \
  echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c -; \
  chmod +x /usr/bin/as-tini-static; \
  \
  # Download and install server
  if [ "${ARCH}" = "x86_64" ]; then \
    pkg_link="${AEROSPIKE_X86_64_LINK}"; sha256="${AEROSPIKE_SHA_X86_64}"; \
  else \
    pkg_link="${AEROSPIKE_AARCH64_LINK}"; sha256="${AEROSPIKE_SHA_AARCH64}"; \
  fi; \
  curl -fsSL "${pkg_link}" -o aerospike.tgz; \
  echo "${sha256} aerospike.tgz" | sha256sum -c -; \
  mkdir aerospike && tar xzf aerospike.tgz --strip-components=1 -C aerospike; \
  rpm -i aerospike/aerospike-server-*.rpm; \
  mkdir -p /var/{log,run}/aerospike /licenses; \
  cp aerospike/LICENSE /licenses; \
  \
  # Install tools
  mkdir -p aerospike/pkg; \
  cd aerospike/pkg && rpm2cpio ../aerospike-tools*.rpm | cpio -idmv && cd ../..; \
  find aerospike/pkg/opt/aerospike/bin/ -user aerospike -group aerospike -exec chown root:root {} + 2>/dev/null || true; \
  mv aerospike/pkg/etc/aerospike/astools.conf /etc/aerospike; \
  if [ -d 'aerospike/pkg/opt/aerospike/bin/asadm' ]; then \
    mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/; \
  else \
    mkdir -p /usr/lib/asadm && mv aerospike/pkg/opt/aerospike/bin/asadm /usr/lib/asadm/; \
  fi; \
  ln -sf /usr/lib/asadm/asadm /usr/bin/asadm; \
  [ -f 'aerospike/pkg/opt/aerospike/bin/asinfo' ] && mv aerospike/pkg/opt/aerospike/bin/asinfo /usr/lib/asadm/; \
  ln -sf /usr/lib/asadm/asinfo /usr/bin/asinfo; \
  \
  # Cleanup
  rm -rf aerospike aerospike.tgz; \
  microdnf remove -y findutils tar gzip xz cpio; \
  microdnf clean all; \
  rm -rf /var/cache/yum; \
  echo "done"

COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh

EXPOSE 3000 3001 3002

ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
