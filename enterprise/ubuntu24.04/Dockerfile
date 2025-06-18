###########################
# ─── Builder Stage ──────

###########################
FROM ubuntu:24.04 AS builder
SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install tools to extract the .deb and verify tini
# This is the very minimum. We are taking pains to make our builder small
# because, despite not ending up in the final image, the builder is
# included in the build context and is a significant source of build
# time.

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    coreutils \
    ar \
    tar \
    xz-utils \
 && rm -rf /var/lib/apt/lists/*

# Create Aerospike user and group
RUN groupadd -r aerospike && \
    useradd -r -g aerospike -d /opt/aerospike -s /usr/sbin/nologin aerospike

COPY aerospike-server_*.deb /tmp/
WORKDIR /tmp/extracted
# Manually extracting the deb, keeping our cypher small
RUN ar x /tmp/aerospike-server_*.deb && \
    tar -xf data.tar.* -C /tmp/rootfs && \
    mkdir -p /tmp/rootfs/licenses /tmp/rootfs/var/{log,run}/aerospike && \
    chown -R aerospike:aerospike /tmp/rootfs

# Download and verify Tini
RUN ARCH="$(dpkg --print-architecture)" && \
    if [ "${ARCH}" = "amd64" ]; then \
      sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
      suffix=""; \
    elif [ "${ARCH}" = "arm64" ]; then \
      sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b; \
      suffix="-arm64"; \
    else \
      echo "Unsupported architecture - ${ARCH}" >&2; exit 1; \
    fi && \
    curl -fsSL "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" \
      --output /tini && \
    echo "${sha256}  /tini" | sha256sum -c - && \
    chmod +x /tini

#############################
# ─── Final Runtime Stage ──
#############################
FROM ubuntu:24.04

# OCI Metadata
LABEL org.opencontainers.image.title="Aerospike Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install only what asd needs to run
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libcurl4 \
    libldap-2.5-0 \
 && rm -rf /var/lib/apt/lists/*

# Recreate the user and group for runtime
RUN groupadd -r aerospike && \
    useradd -r -g aerospike -d /opt/aerospike -s /usr/sbin/nologin aerospike

# Aerospike runtime files, tini, and conf from builder
COPY --from=builder /tmp/rootfs/ /
COPY --from=builder /tini /usr/bin/as-tini-static
COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY --chmod=0755 entrypoint.sh /entrypoint.sh

RUN chown -R aerospike:aerospike /opt/aerospike /etc/aerospike

# Expose standard Aerospike ports
EXPOSE 3000 3001 3002

# Entrypoint via tini (for proper signal handling)
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]
CMD ["asd"]
