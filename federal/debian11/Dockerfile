
#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM debian:bullseye-slim

ARG DEBUG=false

ARG ARTIFACTS_DOMAIN="https://artifacts.aerospike.com"
ARG LINUX_DISTRO=debian11

# AEROSPIKE_VERSION - required - version of the Aerospike database to install.
ARG AEROSPIKE_VERSION=6.2.0.0

# AEROSPIKE_TOOLS_VERSION - required for 6.2+ - version of the aerospike tools
# package which is bundled with the server.
ARG AEROSPIKE_TOOLS_VERSION=8.0.2

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION=federal

ARG AEROSPIKE_SHA_X86_64=eb01c998609077bb66eb00847b9bfe65d7287e9bda0a869f28670bd8f73b6c08
ARG AEROSPIKE_SHA_AARCH64=

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
