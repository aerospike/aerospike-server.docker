
#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM debian:bullseye-slim

ARG DEBUG=false

# AEROSPIKE_EDITION - required - must be "community", "enterprise", or
# "federal".
# By selecting "community" you agree to the "COMMUNITY_LICENSE".
# By selecting "enterprise" you agree to the "ENTERPRISE_LICENSE".
# By selecting "federal" you agree to the "FEDERAL_LICENSE"
ARG AEROSPIKE_EDITION=community

ARG AEROSPIKE_X86_64_LINK="https://artifacts.aerospike.com/aerospike-server-community/6.2.0.0/aerospike-server-community_6.2.0.0_tools-8.0.2_debian11_x86_64.tgz"
ARG AEROSPIKE_SHA_X86_64=7fb6338a5f6587bef50e341951d011404e770ae4c6b87f23c3e66cdd7c5c80d0
ARG AEROSPIKE_AARCH64_LINK="https://artifacts.aerospike.com/aerospike-server-community/6.2.0.0/aerospike-server-community_6.2.0.0_tools-8.0.2_debian11_aarch64.tgz"
ARG AEROSPIKE_SHA_AARCH64=8b4c5b7e7a376bff755b9db36aa0d77a94fa1554f40af1887960c319efe704b8

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
