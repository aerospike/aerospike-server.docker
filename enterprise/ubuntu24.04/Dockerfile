# syntax=docker/dockerfile:1.4

# Builder stage
FROM ubuntu:24.04 AS builder

LABEL org.opencontainers.image.title="Aerospike Server" \
      org.opencontainers.image.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
      org.opencontainers.image.documentation="https://hub.docker.com/_/aerospike" \
      org.opencontainers.image.base.name="docker.io/library/ubuntu:24.04" \
      org.opencontainers.image.source="https://github.com/aerospike/aerospike-server.docker" \
      org.opencontainers.image.vendor="Aerospike" \
      org.opencontainers.image.url="https://github.com/aerospike/aerospike-server.docker"

ARG AEROSPIKE_EDITION=""
ENV AEROSPIKE_LINUX_BASE="ubuntu:24.04"

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

# Install build dependencies and extract server package
RUN \
  { \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update -y; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      procps \
      libcurl4 \
      libldap-2.4.2; \
    # Create required directories
    mkdir -p /var/{log,run}/aerospike; \
    mkdir -p /licenses; \
  }

# Copy the local .deb file into the builder
COPY aerospike-server-enterprise_*.deb /tmp/

# Install the server package
RUN dpkg -i /tmp/aerospike-server-enterprise_*.deb && \
    rm -rf /tmp/aerospike-server-enterprise_*.deb

# Final stage
FROM ubuntu:24.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    procps \
    libcurl4 \
    libldap-2.4.2 \
    && rm -rf /var/lib/apt/lists/*

# Copy necessary files from builder
COPY --from=builder /usr/bin/asd /usr/bin/asd
COPY --from=builder /etc/aerospike /etc/aerospike
COPY --from=builder /var/log/aerospike /var/log/aerospike
COPY --from=builder /var/run/aerospike /var/run/aerospike
COPY --from=builder /var/opt/aerospike /var/opt/aerospike
COPY --from=builder /licenses /licenses

# Copy configuration and entrypoint
COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh

# Install tini
RUN ARCH="$(dpkg --print-architecture)" && \
    if [ "${ARCH}" = "amd64" ]; then \
      sha256=d1f6826dd70cdd88dde3d5a20d8ed248883a3bc2caba3071c8a3a9b0e0de5940; \
      suffix=""; \
    elif [ "${ARCH}" = "arm64" ]; then \
      sha256=1c398e5283af2f33888b7d8ac5b01ac89f777ea27c85d25866a40d1e64d0341b; \
      suffix="-arm64"; \
    else \
      echo "Unsuported architecture - ${ARCH}" >&2; \
      exit 1; \
    fi && \
    curl -fsSL "https://github.com/aerospike/tini/releases/download/1.0.1/as-tini-static${suffix}" --output /usr/bin/as-tini-static && \
    echo "${sha256} /usr/bin/as-tini-static" | sha256sum -c - && \
    chmod +x /usr/bin/as-tini-static

# Expose Aerospike ports
EXPOSE 3000 3001 3002

# Set entrypoint with tini
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Default command
CMD ["asd"]
