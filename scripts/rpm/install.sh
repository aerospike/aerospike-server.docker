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
