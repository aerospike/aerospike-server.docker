#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:xenial

ENV AEROSPIKE_VERSION 3.9.1.1
ENV UBUNTU_VERSION 16
ENV AEROSPIKE_SHA256 05d049f83a1fce9d4acc6ad6f1fbbe86af2dfb462d47eafbfae1ae4dbbb943c1           

# Install Aerospike


RUN \
  apt-get update -y \
  && apt-get install -y wget python logrotate \
  && wget "https://www.aerospike.com/artifacts/aerospike-server-community/${AEROSPIKE_VERSION}/aerospike-server-community-${AEROSPIKE_VERSION}-ubuntu16.04.tgz" -O aerospike-server.tgz \
  && wget "http://www.aerospike.com/download/tools/${AEROSPIKE_VERSION}/artifact/ubuntu${UBUNTU_VERSION}" -O aerospike-tools.tgz \
  && echo "$AEROSPIKE_SHA256 *aerospike-server.tgz" | sha256sum -c - \
  && mkdir aerospike \
  && tar xzf aerospike-server.tgz --strip-components=1 -C aerospike \
  && dpkg -i aerospike/aerospike-server-*.deb \
  && mkdir -p /var/log/aerospike/ \
  && mkdir -p /var/run/aerospike/ \
  && rm -rf aerospike-server.tgz aerospike /var/lib/apt/lists/* \
  && dpkg -r wget openssl ca-certificates \
  && dpkg --purge wget openssl ca-certificates \
  && mkdir aerospike-tools \
  && tar xzf aerospike-tools.tgz --strip-components=1 -C aerospike-tools \
  && ./aerospike-tools/asinstall


# Add the Aerospike configuration specific to this dockerfile
COPY aerospike.conf /etc/aerospike/aerospike.conf
COPY entrypoint.sh /entrypoint.sh
# Mount the Aerospike data directory
VOLUME ["/opt/aerospike/data"]
# VOLUME ["/etc/aerospike/"]


# Expose Aerospike ports
#
#   3000 – service port, for client connections
#   3001 – fabric port, for cluster communication
#   3002 – mesh port, for cluster heartbeat
#   3003 – info port
#
EXPOSE 3000 3001 3002 3003

# Execute the run script in foreground mode
ENTRYPOINT ["/entrypoint.sh"]
CMD ["asd"]
