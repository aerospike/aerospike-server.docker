#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM debian:7


# Work from /tmp
WORKDIR /tmp

# Install Aerospike
RUN \
  apt-get update -y \
  && apt-get install -y wget logrotate \
  && wget --no-check-certificate https://www.aerospike.com/artifacts/aerospike-server-community/3.4.1/aerospike-server-community-3.4.1-debian7.tgz \
  && wget --no-check-certificate -O /tmp/CHECKSUM https://www.aerospike.com/artifacts/aerospike-server-community/3.4.1/aerospike-server-community-3.4.1-debian7.tgz.sha256  \
  && sha256sum -c /tmp/CHECKSUM \
  && tar xzf aerospike-server-community-*.tgz \
  && cd aerospike-server-community-* \
  && dpkg -i aerospike-server-* 

# Add the Aerospike configuration specific to this dockerfile
ADD aerospike.conf /etc/aerospike/aerospike.conf

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

# Execute the run script in foreground mode
CMD ["/usr/bin/asd","--foreground"]
