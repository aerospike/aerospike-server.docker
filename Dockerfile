#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM debian:buster-slim

ENV AEROSPIKE_VERSION 6.0.0.6
ENV AEROSPIKE_SHA256 0a9a3c60a0ab85ac53b9c2feac378036a11b04218bc1f242adce325dfce90c12

# Install Aerospike Server and Tools


RUN \
  apt-get update -y \
  && apt-get install -y iproute2 procps dumb-init wget python python3 python3-distutils lua5.2 gettext-base libcurl4-openssl-dev  \
  && wget "https://www.aerospike.com/artifacts/aerospike-server-community/${AEROSPIKE_VERSION}/aerospike-server-community-${AEROSPIKE_VERSION}-debian10.tgz" -O aerospike-server.tgz \
  && echo "$AEROSPIKE_SHA256 *aerospike-server.tgz" | sha256sum -c - \
  && mkdir aerospike \
  && tar xzf aerospike-server.tgz --strip-components=1 -C aerospike \
  && dpkg -i aerospike/aerospike-server-*.deb \
  && dpkg -i aerospike/aerospike-tools-*.deb \
  && mkdir -p /var/log/aerospike/ \
  && mkdir -p /var/run/aerospike/ \
  && rm -rf aerospike-server.tgz aerospike /var/lib/apt/lists/* \
  && rm -rf /opt/aerospike/lib/java \
  && dpkg -r wget ca-certificates openssl xz-utils\
  && dpkg --purge wget ca-certificates openssl xz-utils\
  && apt-get purge -y \
  && apt autoremove -y \
  # Remove symbolic links of aerospike tool binaries
  # Move aerospike tool binaries to /usr/bin/
  # Remove /opt/aerospike/bin
  && find /usr/bin/ -lname '/opt/aerospike/bin/*' -delete \
  && find /opt/aerospike/bin/ -user aerospike -group aerospike -exec chown root:root {} + \
  # Since tools release 7.0.5, asadm has been moved from /opt/aerospike/bin/asadm to /opt/aerospike/bin/asadm/asadm (inside an asadm directory)
  && if [ -d '/opt/aerospike/bin/asadm' ]; \
  then \
  mv /opt/aerospike/bin/asadm /usr/lib/; \
  ln -s /usr/lib/asadm/asadm /usr/bin/asadm; \
    # Since tools release 7.1.1, asinfo has been moved from /opt/aerospike/bin/asinfo to /opt/aerospike/bin/asadm/asinfo (inside an asadm directory)
    if [ -f /usr/lib/asadm/asinfo ]; \
    then \
    ln -s /usr/lib/asadm/asinfo /usr/bin/asinfo; \
    fi \
  fi \
  && mv /opt/aerospike/bin/* /usr/bin/ \
  && rm -rf /opt/aerospike/bin



# Add the Aerospike configuration specific to this dockerfile
COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
COPY entrypoint.sh /entrypoint.sh

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

# Runs as PID 1 /usr/bin/dumb-init -- /my/script --with --args"
# https://github.com/Yelp/dumb-init

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/entrypoint.sh"]
# Execute the run script in foreground mode
CMD ["asd"]
