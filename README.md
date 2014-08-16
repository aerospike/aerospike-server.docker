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

The following will run `asd` with all the exposed ports forward to the host machine.

	docker run -tid --name aerospike -p 3000:3000 -p 3001:3001 -p 3002:3002 -p 3003:3003 aerospike/aerospike-server
	
**NOTE** Although this is the simplest method to getting Aerospike up and running, but it is not the prefered method. To properly run the container, please specify an **alternative configuration** with the **access-address** defined.

### Advanced Usage 


#### Custom Configuration

By default, `asd` will use the configuration file in `/etc/aerospike/aerospike.conf`, which is added to the directory by the Dockerfile. To provide a custom configuration, you should first mount a directory containing the file using the `-v` option for `docker`:

	-v <DIRECTORY>:/opt/aerospike/etc

Where `<DIRECTORY>` is the path to a directory containing your custom configuration file. Next, you will want to tell `asd` to use a configuration file from `/opt/aerospike/etc`, by using the `--config-file` option for `aerospike/aerospike-server`:
 
	--config-file /opt/aerospike/etc/aerospike.conf

This will use tell `asd` to use the file in `/opt/aerospike/etc/aerospike.conf`, which is mapped to `<DIRECTORY>/aerospike.conf`.

A full example:

	docker run -tid -v <DIRECTORY>:/opt/aerospike/etc --name aerospike -p 3000:3000 -p 3001:3001 -p 3002:3002 -p 3003:3003 aerospike/aerospike-server --config-file /opt/aerospike/etc/aerospike.conf


#### Persistent Data Directory

With Docker, the files within the container are not persisted. To persist the data, you will want to mount a directory from the host to the guest's `/opt/aerospike/data` using the `-v` option:

	-v <DIRECTORY>:/opt/aerospike/data

Where `<DIRECTORY>` is the path to a directory containing your data files.

A full example:

	docker run -tid -v <DIRECTORY>:/opt/aerospike/data --name aerospike -p 3000:3000 -p 3001:3001 -p 3002:3002 -p 3003:3003 aerospike/aerospike-server


#### Multicast Networking

We are currently working to figure out how to best support multicast. For the time being, it will be best to setup Mesh networking (see below). We are open to pull-requests with proposals on how to implement multicast for our Dockerfile.

#### Mesh Networking

Mesh networking requires setting up links between each node in the cluster. This can be achieved in two ways:

1. Define a configuration for each node in the cluster, as defined in [Network Heartbeat Configuration](http://www.aerospike.com/docs/operations/configure/network/heartbeat/#mesh-unicast-heartbeat).

2. Use `asinfo` to send the `tip` command, to make the node aware of another node, as defined in [tip command in asinfo](http://www.aerospike.com/docs/tools/asinfo/#tip).





