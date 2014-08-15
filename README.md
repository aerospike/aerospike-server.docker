## Aerospike Server Dockerfile

This repository contains the Dockerfile for [Aerospike](http://aerospike.com). 

### Dependencies

- [ubuntu:14.04](https://registry.hub.docker.com/_/ubuntu/)

### Installation

1. Install [Docker](https://www.docker.io/).

2. Download from public [Docker Registry](https://index.docker.io/):

		docker pull aerospike/aerospike-server

   _Alternatively, you can build an image from Dockerfile:_
   
   		docker build -t="aerospike/aerospike-server" github.com/aerospike/aerospike-server.docker

### Usage

The following are options for running Aerospike Daemon `asd`.

#### Run `asd`

The following will run `asd` with all the exposed ports forward to the host machine.

	docker run -tid --name aerospike -p 3000:3000 -p 3001:3001 -p 3002:3002 -p 3003:3003 aerospike/aerospike-server

#### Run `asd` with persistent data directory

To have the data that is persisted by aerospike be available between container runs, you can mount a directory from the host by specifying the `-v` option:

	docker run -tid -v <DIRECTORY>:/opt/aerospike/data --name aerospike -p 3000:3000 -p 3001:3001 -p 3002:3002 -p 3003:3003 aerospike/aerospike-server


#### Run `asd` with alternative configuration
	
By default, `asd` will use the configuration file in `/etc/aerospike/aerospike.conf`, which is added to the direcroty by the Dockerfile. To provide an alternate configuration, you should first mount a directory containing the file using the `-v` option, then specify the path using the `--config-file` argument to the container:

	docker run -tid -v <DIRECTORY>:/opt/aerospike/etc --name aerospike -p 3000:3000 -p 3001:3001 -p 3002:3002 -p 3003:3003 aerospike/aerospike-server --config-file /opt/aerospike/etc/aerospike.conf
	
