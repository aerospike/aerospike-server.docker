# This file contains the targets for the test images.
# This file is auto-generated by the update.sh script and will be wiped out by the update.sh script.
# Please don't edit this file.
#
# Build all test/push images:
#      docker buildx bake -f bake.hcl [test | push] --progressive plain [--load | --push]
# Build selected images:
#      docker buildx bake -f bake.hcl [target name, ...] --progressive plain [--load | --push]

#------------------------------------- test -----------------------------------

group "test" {
	targets=["enterprise_debian10_amd64", "community_debian10_amd64"]
}

target "enterprise_debian10_amd64" {
	 tags=["aerospike/aerospike-server-enterprise-amd64:5.7.0.26", "aerospike/aerospike-server-enterprise-amd64:latest"]
	 platforms=["linux/amd64"]
	 context="./enterprise/debian10"
}

target "community_debian10_amd64" {
	 tags=["aerospike/aerospike-server-community-amd64:5.7.0.26", "aerospike/aerospike-server-community-amd64:latest"]
	 platforms=["linux/amd64"]
	 context="./community/debian10"
}

#------------------------------------ push -----------------------------------

group "push" {
	targets=["enterprise_debian10", "community_debian10"]
}

target "enterprise_debian10" {
	 tags=["aerospike/aerospike-server-enterprise:5.7.0.26", "aerospike/aerospike-server-enterprise:5.7.0.26_1"]
	 platforms=["linux/amd64"]
	 context="./enterprise/debian10"
}

target "community_debian10" {
	 tags=["aerospike/aerospike-server:5.7.0.26", "aerospike/aerospike-server:5.7.0.26_1"]
	 platforms=["linux/amd64"]
	 context="./community/debian10"
}

