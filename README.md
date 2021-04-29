# Aerospike Community Edition Docker Image

## What is Aerospike?
[Aerospike](http://aerospike.com) is a distributed NoSQL database purposefully designed for high performance web scale applications. Aerospike supports key-value and document data models, and has multiple data types including List, Map, HyperLogLog, GeoJSON, and Blob. Aerospike's patented hybrid memory architecture delivers predictable high performance at scale and high data density per node.

![aerospike_square_logo](https://user-images.githubusercontent.com/133497/114279415-7425dc00-99e9-11eb-8eab-104042d38c44.png)

 * [Getting Started](#getting-started)
   * [Running an Aerospike node](#running-an-aerospike-node)
 * [Connecting to your Aerospike contianer](#connecting-to-your-aerospike-contianer)
   * [Using aql](#using-aql)
   * [Using asadm](#using-asadm)
 * [Advanced Configuration](#advanced-configuration)
   * [Injecting configuration parameters](#injecting-configuration-parameters)
     * [List of template variables](#list-of-template-variables)
   * [Using a custom configuration file](#using-a-custom-configuration-file)
   * [Persistent Data Directory](#persistent-data-directory)
   * [Block Storage](#block-storage)
   * [Persistent Lua Cache](#persistent-lua-cache)
   * [A note about security](#a-note-about-security)
 * [Clustering](#clustering)
   * [Configuring the node's access address](#configuring-the-nodes-access-address)
   * [Mesh Clustering](#mesh-clustering)
 * [Sending Performance Data to Aerospike](#sending-performance-data-to-aerospike)
 * [Image Versions](#image-versions)
 * [Reporting Issues](#reporting-issues)
 * [License](#license)

## Getting Started <a id="getting-started"></a>
Aerospike Community Edition supports the same developer APIs as Aerospike
Enterprise Edition, and differs in ease of operation and enterprise features.
See the [product matrix](https://www.aerospike.com/products/product-matrix/) for
more.

Anyone can [sign up](https://www.aerospike.com/lp/try-now/) to get an
evaluation feature key file for a full-featured, single-node Aerospike Enterprise
Edition.

### Running an Aerospike node <a id="running-an-aerospike-node"></a>

```sh
docker run -d --name aerospike -p 3000-3002:3000-3002 aerospike/aerospike-server
```

## Connecting to your Aerospike contianer <a id="connecting-to-you-aerospike-container"></a>

You can use the latest aerospike-tools image to connect to your Aerospike
container.

### Using aql <a id="using-aql"></a>

```sh
docker run -ti aerospike/aerospike-tools:latest aql -h  $(docker inspect -f '{{.NetworkSettings.IPAddress }}' aerospike)

Seed:         172.17.0.2
User:         None
Config File:  /etc/aerospike/astools.conf /root/.aerospike/astools.conf 
Aerospike Query Client
Version 5.0.1
C Client Version 4.6.17
Copyright 2012-2020 Aerospike. All rights reserved.
aql> show namespaces
+------------+
| namespaces |
+------------+
| "test"     |
+------------+
[127.0.0.1:3000] 1 row in set (0.002 secs)

OK

aql> help
```

### Using asadm <a id="using-asadm"></a>

```sh
docker run -ti aerospike/aerospike-tools:latest asadm -h  $(docker inspect -f '{{.NetworkSettings.IPAddress }}' aerospike)

Seed:        [('172.17.0.2', 3000, None)]
Config_file: /root/.aerospike/astools.conf, /etc/aerospike/astools.conf
Aerospike Interactive Shell, version 2.0.1

Found 1 nodes
Online:  172.17.0.2:3000

Admin> info
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~Network Information (2021-04-20 01:57:37 UTC)~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
           Node|         Node ID|             IP|    Build|Migrations|~~~~~~~~~~~~~~~~~~Cluster~~~~~~~~~~~~~~~~~~|Client|  Uptime
               |                |               |         |          |Size|         Key|Integrity|      Principal| Conns|        
172.17.0.2:3000|*BB9020011AC4202|172.17.0.2:3000|C-5.5.0.9|   0.000  |   1|3FA2C989BDC9|True     |BB9020011AC4202|     4|00:06:54
Number of rows: 1

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~Namespace Usage Information (2021-04-20 01:57:37 UTC)~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Namespace|           Node|  Total|Expirations|Evictions|  Stop|~~~~~~~~~~~Disk~~~~~~~~~~~|~~~~~~~~~~Memory~~~~~~~~~|~Primary~
         |               |Records|           |         |Writes|    Used|Used%|HWM%|Avail%|    Used|Used%|HWM%|Stop%|~~Index~~
         |               |       |           |         |      |        |     |    |      |        |     |    |     |     Type
test     |172.17.0.2:3000|0.000  |    0.000  |  0.000  |False |0.000 B |    0|   0|    99|0.000 B |    0|   0|   90|undefined
test     |               |0.000  |    0.000  |  0.000  |      |0.000 B |     |    |      |0.000 B |     |    |     |         
Number of rows: 1

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~Namespace Object Information (2021-04-20 01:57:37 UTC)~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Namespace|           Node|Rack|  Repl|  Total|~~~~~~~~~~Objects~~~~~~~~~~|~~~~~~~~~Tombstones~~~~~~~~|~~~~Pending~~~~
         |               |  ID|Factor|Records| Master|  Prole|Non-Replica| Master|  Prole|Non-Replica|~~~~Migrates~~~
         |               |    |      |       |       |       |           |       |       |           |     Tx|     Rx
test     |172.17.0.2:3000|   0|     1|0.000  |0.000  |0.000  |    0.000  |0.000  |0.000  |    0.000  |0.000  |0.000  
test     |               |    |      |0.000  |0.000  |0.000  |    0.000  |0.000  |0.000  |    0.000  |0.000  |0.000  
Number of rows: 1
```

## Advanced Configuration <a id="advanced-configuration"></a>
The Aerospike CE Docker image has a default configuration file template
that can be populated with individual configuration parameters.
Alternatively, it can be replaced with a custom configuration file.

The following sections describe both advanced options.

### Injecting configuration parameters <a id="injecting-configuration-parameters"></a>

You can inject parameters into the configuration template using container-side
environment variables with the `-e` flag.

For example, to set the default [namespace](https://www.aerospike.com/docs/architecture/data-model.html)
name to _demo_:

```sh
docker run -d --name aerospike -e "NAMESPACE=demo" -p 3000-3002:3000-3002 -v /my/dir:/opt/aerospike/etc/ aerospike/aerospike-server
```

Injecting configuration parameters into the configuration template isn't
compatible with using a custom configuration file. You can use one or the other.

#### List of template variables <a id="list-of-template-variables"></a>

  * `SERVICE_THREADS` - the [`service_threads`](https://www.aerospike.com/docs/reference/configuration/index.html#service-threads). Default: Number of vCPUs
  * `LOGFILE` - the [`file`](https://www.aerospike.com/docs/reference/configuration/index.html#file) param of the `logging` context. Default: /dev/null, do not log to file, log to stdout
  * `SERVICE_ADDRESS` - the bind [`address`](https://www.aerospike.com/docs/reference/configuration/index.html#address) of the `networking.service` subcontext. Default: any
  * `SERVICE_PORT` - the [`port`](https://www.aerospike.com/docs/reference/configuration/index.html#port) of the `networking.service` subcontext. Default: 3000
  * `HB_ADDRESS` - the `networking.heartbeat` [`address`](https://www.aerospike.com/docs/reference/configuration/index.html#address) for cross cluster mesh. Default: any
  * `HB_PORT` -  the [`port`](https://www.aerospike.com/docs/reference/configuration/index.html#port) for `networking.heartbeat` communications. Default: 3002
  * `FABRIC_ADDRESS` - the [`address`](https://www.aerospike.com/docs/reference/configuration/index.html#address) of the `networking.fabric` subcontext. Default: any
  * `FABRIC_PORT` - the [`port`](https://www.aerospike.com/docs/reference/configuration/index.html#port) of the `networking.fabric` subcontext. Default: 3001

The single preconfigured namespace is [in-memory with filesystem persistence](https://www.aerospike.com/docs/operations/configure/namespace/storage/#recipe-for-a-hdd-storage-engine-with-data-in-index-engine)
  * `NAMESPACE` - the name of the namespace. Default: test
  * `REPL_FACTOR` - the namespace [`replication-factor`](https://www.aerospike.com/docs/reference/configuration/index.html#replication-factor). Default: 2
  * `MEM_GB` - the namespace [`memory-size`](https://www.aerospike.com/docs/reference/configuration/index.html#memory-size). Default: 1, the unit is always `G` (GB)
  * `DEFAULT_TTL` - the namespace [`default-ttl`](https://www.aerospike.com/docs/reference/configuration/index.html#default-ttl). Default: 30d
  * `STORAGE_GB` - the namespace persistence `file` size. Default: 4, the unit is always `G` (GB)
  * `NSUP_PERIOD` - the namespace [`nsup-period`](https://www.aerospike.com/docs/reference/configuration/index.html#nsup-period). Default: 120 , nsup-period in seconds 

### Using a custom configuration file <a id="using-a-custom-configuration-file"></a>
You can override the use of the configuration file template by providing your own
aerospike.conf, as described in
[Configuring Aerospike Database](https://www.aerospike.com/docs/operations/configure/index.html).

You should first `-v` map a local directory, which Docker will bind mount.
Next, drop your aerospike.conf file into this directory.
Finally, use the `--config-file` option to tell Aerospike where in the
container the configuration file is (the default path is
/etc/aerospike/aerospike.conf).

For example:

```sh
docker run -d -v /opt/aerospike/etc/:/opt/aerospike/etc/ --name aerospike -p 3000-3002:3000-3002 aerospike/aerospike-server --config-file /opt/aerospike/etc/aerospike.conf
```

### Persistent data directory <a id="persistent-data-directory"></a>

With Docker, the files within the container are not persisted past the life of
the container. To persist data, you will want to mount a directory from the
host to the container's /opt/aerospike/data using the `-v` option:

For example:

```sh
docker run -d  -v /opt/aerospike/data:/opt/aerospike/data  -v /opt/aerospike/etc:/opt/aerospike/etc/ --name aerospike -p 3000-3002:3000-3002 aerospike/aerospike-server
```

The example above uses the configuration template, where the single defined
namespace is in-memory with file-based persistence. Just mounting the predefined
/opt/aerospike/data directory enables the data to be persisted on the host.

Alternatively, a custom configuration file is used with the parameter
`file` set to be a file in the mounted /opt/aerospike/data, such as in the
following config snippet:

```
namespace test {
	# :
	storage-engine device {
		file /opt/aerospike/data/test.dat
		filesize 4G
		data-in-memory true
	}
}
```

In this example we also mount the data directory in a similar way, using a
custom configuration file

```sh
docker run -d -v /opt/aerospike/data:/opt/aerospike/data -v /opt/aerospike/etc/:/opt/aerospike/etc/ --name aerospike -p 3000-3002:3000-3002 aerospike/aerospike-server --config-file /opt/aerospike/etc/aerospike.conf
```

### Block Storage <a id="block-storage"></a>

Docker provides an ability to expose a host's block devices to a running container.
The `--device` option can be used to map a host block device within a container.

Update the `storage-engine device` section of the namespace in the custom
aerospike configuration file.

```
namespace test {
	# :
	storage-engine device {
		device /dev/xvdc
			write-block-size 128k
	}
}
```

Now to map a host drive /dev/sdc to /dev/xvdc on a container

```sh
docker run -d --device '/dev/sdc:/dev/xvdc' -v /opt/aerospike/etc/:/opt/aerospike/etc/ --name aerospike -p 3000-3002:3000-3002 aerospike/aerospike-server --config-file /opt/aerospike/etc/aerospike.conf
```

### Persistent Lua cache <a id="persistent-lua-cache"></a>

Upon restart, your Lua cache will become emptied. To persist the cache, you
will want to mount a directory from the host to the container's
`/opt/aerospike/usr/udf/lua` using the `-v` option:

```sh
docker run -d -v /opt/aerospike/lua:/opt/aerospike/usr/udf/lua -v /opt/aerospike/data:/opt/aerospike/data --name aerospike -p 3000-3002:3000-3002 aerospike/aerospike-server
```

### A note about security <a id="a-note-about-security"></a>

[And Now for a Security Reminder](https://www.aerospike.com/blog/and-now-for-a-security-reminder/)
that bad things can happen to good people.

Also see the knowledge base article
[How To secure Aerospike database servers](https://discuss.aerospike.com/t/how-to-secure-aerospike-database-servers/7804).

## Clustering <a id="clustering"></a>

### Configuring the node's access address <a id="configuring-the-nodes-access-address"></a>

In order for the Aerospike node to properly broadcast its address to the cluster
and applications, the [`access-address`](https://www.aerospike.com/docs/reference/configuration/index.html#access-address)
configuration parameter needs to be set in the configuration file. If it is not
set, then the IP address within the container will be used, which is not
accessible to other nodes.

```
	network {
		service {
			address any                  # Listening IP Address
			port 3000                    # Listening Port
			access-address 192.168.1.100 # IP Address used by cluster nodes and applications
		}
```

### Mesh Clustering <a id="mesh-clustering"></a>

Mesh networking requires setting up links between each node in the cluster.
This can be achieved in two ways:

 1. Add a configuration for each node in the cluster, as defined in [Network Heartbeat Configuration](http://www.aerospike.com/docs/operations/configure/network/heartbeat/#mesh-unicast-heartbeat).
 2. Use `asinfo` to send the `tip` command, to make the node aware of another node, as defined in [tip command in asinfo](http://www.aerospike.com/docs/tools/asinfo/#tip).

For more, see [How do I get a 2 nodes Aerospike cluster running quickly in Docker without editing a single file?](https://medium.com/aerospike-developer-blog/how-do-i-get-a-2-node-aerospike-cluster-running-quickly-in-docker-without-editing-a-single-file-1c2a94564a99?source=friends_link&sk=4ff6a22f0106596c42aa4b77d6cdc3a5)

## Sending Performance Data to Aerospike <a id="sending-performance-data-to-aerospike"></a>

Aerospike Telemetry is a feature that allows us to collect certain use data – not the database data – on your Aerospike Community Edition server use. 
We’d like to know when clusters are created and destroyed, cluster size, cluster workload, how often queries are run, whether instances are deployed purely in-memory or with Flash. 
Aerospike Telemetry collects information from running Community Edition server instances every 10 minutes. The data helps us to understand how the product is being used,
identify issues, and create a better experience for the end user. [More Info](http://www.aerospike.com/aerospike-telemetry/)

## Image Versions <a id="image-versions"></a>

These images are based on [debian:strech-slim](https://hub.docker.com/_/debian).

## Reporting Issues <a id="reporting-issues"></a>

If you have any problems with or questions about this image, please contact us on the [Aerospike Forums](discuss.aerospike.com) or open an issue in [aerospike/aerospike-server.docker](https://github.com/aerospike/aerospike-server.docker/issues).

## License <a id="license"></a>

Refer to the license information in the [aerospike/aerospike-server](https://github.com/aerospike/aerospike-server) repository.
