#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM debian:7

ENV AEROSPIKE_VERSION 3.6.4 
ENV AEROSPIKE_SHA256 f946b51ac0e55c3a01f8ce71976bb89c29f894c23f7b4e5bd0a0d4501915c559   

# Install Aerospike with a static UID/GID for the aerospike user/group
RUN \
  apt-get update -y \
  && apt-get install -y wget logrotate ca-certificates \
  && wget "https://www.aerospike.com/artifacts/aerospike-server-community/${AEROSPIKE_VERSION}/aerospike-server-community-${AEROSPIKE_VERSION}-debian7.tgz" -O aerospike-server.tgz \
  && echo "$AEROSPIKE_SHA256 *aerospike-server.tgz" | sha256sum -c - \
  && mkdir aerospike \
  && tar xzf aerospike-server.tgz --strip-components=1 -C aerospike \
  && groupadd -g 24183 aerospike \
  && useradd -r -u 24183 -d /opt/aerospike -g aerospike aerospike \
  && dpkg -i aerospike/aerospike-server-*.deb \
  && apt-get purge -y --auto-remove wget ca-certificates \
  && rm -rf aerospike-server.tgz aerospike /var/lib/apt/lists/*

# Copy the Aerospike configuration specific to this dockerfile
COPY aerospike.conf /etc/aerospike/aerospike.conf

# Mount the Aerospike data directory
VOLUME ["/opt/aerospike/data"]

# Expose Aerospike ports
#
#   3000 – service port, for client connections
#   3001 – fabric port, for cluster communication
#   3002 – mesh port, for cluster heartbeat
#   3003 – info port
#
EXPOSE 3000 3001 3002 3003

COPY docker-entrypoint.sh /docker-entrypoint.sh

# Run commands in the container as the aerospike user by default
USER aerospike

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["asd"]
