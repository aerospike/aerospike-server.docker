
#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM debian:bullseye-slim

LABEL \
  maintainer="Aerospike, Inc. <developers@aerospike.com>" \
  name="aerospike-enterprise" \
  vendor="Aerospike" \
  version="6.1.0.5" \
  release="1" \
  summary="Aerospike Server Enterprise Edition" \
  description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions." \
  io.k8s.display-name="Aerospike Server Enterprise Edition 6.1.0.5" \
  io.k8s.description="Aerospike is a real-time database with predictable performance at petabyte scale with microsecond latency over billions of transactions."

ARG DEBUG="false"

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION="enterprise"

ARG AEROSPIKE_X86_64_LINK="https://artifacts.aerospike.com/aerospike-server-enterprise/6.1.0.5/aerospike-server-enterprise-6.1.0.5-debian11.tgz"
ARG AEROSPIKE_SHA_X86_64="0043d83a4486f0e4957b6d8401d550d4478db7820e88c66e941951fb7ef03923"
ARG AEROSPIKE_AARCH64_LINK=""
ARG AEROSPIKE_SHA_AARCH64=""

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Aerospike Server and Tools
COPY scripts/bootstrap.sh /bootstrap.sh
RUN ./bootstrap.sh && rm bootstrap.sh

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

COPY scripts/entrypoint.sh /entrypoint.sh

# Tini init set to restart ASD on SIGUSR1 and terminate ASD on SIGTERM
ENTRYPOINT ["/usr/bin/as-tini-static", "-r", "SIGUSR1", "-t", "SIGTERM", "--", "/entrypoint.sh"]

# Execute the run script in foreground mode
CMD ["asd"]
