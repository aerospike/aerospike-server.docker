#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM debian:stretch-slim 

ENV AEROSPIKE_VERSION 4.5.3.3
ENV AEROSPIKE_SHA256 840eec1223319bc82b8f7db6a155631bc2f991b5de975c45042c90ce39b3d058

# Install Aerospike Server and Tools
RUN \
  apt-get update -y \
  && apt-get install -y wget python lua5.2 gettext-base \
  && wget "https://www.aerospike.com/artifacts/aerospike-server-community/${AEROSPIKE_VERSION}/aerospike-server-community-${AEROSPIKE_VERSION}-debian9.tgz" -O aerospike-server.tgz \
  && echo "$AEROSPIKE_SHA256 *aerospike-server.tgz" | sha256sum -c - \
  && mkdir aerospike \
  && tar xzf aerospike-server.tgz --strip-components=1 -C aerospike \
  && dpkg -i aerospike/aerospike-server-*.deb \
  && dpkg -i aerospike/aerospike-tools-*.deb \
  && mkdir -p /var/log/aerospike/ \
  && mkdir -p /var/log/aerospike/ \
  && chgrp -R 0 /var/log/aerospike \
  && mkdir -p /var/run/aerospike/ \
  && chgrp -R 0 /var/run/aerospike \
  && chmod -R g+rwX /var/run/aerospike \
  && chgrp -R 0 /opt/aerospike/smd \
  && chmod -R g+rwX /opt/aerospike/smd \
  && chgrp -R 0 /opt/aerospike/usr \
  && chmod -R g+rwX /opt/aerospike/usr \
  && chgrp -R 0 /opt/aerospike/data \
  && chmod -R g+rwX /opt/aerospike/data \
  && chgrp -R 0 /etc/aerospike \
  && chmod -R g+rwX /etc/aerospike \
  && rm -rf aerospike-server.tgz aerospike /var/lib/apt/lists/* \
  && rm -rf /opt/aerospike/lib/java \
  && dpkg -r wget ca-certificates openssl xz-utils\
  && dpkg --purge wget ca-certificates openssl xz-utils\
  && apt-get purge -y \
  && apt autoremove -y 

  


# Add the Aerospike configuration specific to this dockerfile
COPY aerospike.template.conf /etc/aerospike/aerospike.template.conf
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
