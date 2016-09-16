#
# Aerospike Server Dockerfile
#
# http://github.com/aerospike/aerospike-server.docker
#

FROM ubuntu:xenial

ENV AEROSPIKE_VERSION 3.9.1.1
ENV AEROSPIKE_SHA256 05d049f83a1fce9d4acc6ad6f1fbbe86af2dfb462d47eafbfae1ae4dbbb943c1           

# Install Aerospike

# Install openssl as a dependency to wget with latest patch for security vulnerabilities
# Vulnerabilities: CVE-2016-2109,CVE-2016-2177
RUN \
  apt-get update -y \
  && apt-get install -y wget make gcc \
  && wget http://http.us.debian.org/debian/pool/main/o/openssl/openssl_1.0.2h-1_amd64.deb \
  && wget http://http.us.debian.org/debian/pool/main/o/openssl/libssl1.0.2_1.0.2h-1_amd64.deb \
  && wget http://http.us.debian.org/debian/pool/main/c/ca-certificates/ca-certificates_20160104_all.deb \
  && echo "ff3524b274038b53e2129c1cbc96b5078511e9214c5b3a2d5f5ea3dc59ca3abd ca-certificates_20160104_all.deb" | sha256sum -c - \
  && echo "83035ac443512f7d2d9867cd50c84bc8a8e7a62b93e1c0ec1b6b9f678a833e4f libssl1.0.2_1.0.2h-1_amd64.deb" | sha256sum -c - \
  && echo "605c2ca88b26ca37968fccd39887820d3cd1d704c9604a3b38aa5a4fc1cf6bbf openssl_1.0.2h-1_amd64.deb" | sha256sum -c - \
  && dpkg -i libssl1.0.2_1.0.2h-1_amd64.deb \
  && dpkg -i openssl_1.0.2h-1_amd64.deb \
  && dpkg -i ca-certificates_20160104_all.deb

# Install Aerospike
RUN \
  apt-get update -y \
  && apt-get install -y  python logrotate \
  && wget -O aerospike-server.tgz "https://www.aerospike.com/artifacts/aerospike-server-community/${AEROSPIKE_VERSION}/aerospike-server-community-${AEROSPIKE_VERSION}-ubuntu16.04.tgz" \
  && echo "$AEROSPIKE_SHA256 *aerospike-server.tgz" | sha256sum -c - \
  && mkdir aerospike \
  && tar xzf aerospike-server.tgz --strip-components=1 -C aerospike \
  && dpkg -i aerospike/aerospike-server-*.deb \
  && mkdir -p /var/log/aerospike/ \
  && mkdir -p /var/run/aerospike/ \
  && rm -rf aerospike-server.tgz aerospike /var/lib/apt/lists/* \
  && dpkg -r wget openssl ca-certificates \
  && dpkg --purge wget openssl ca-certificates


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
