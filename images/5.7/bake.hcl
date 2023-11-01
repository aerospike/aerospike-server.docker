# This file contains the targets for the test images.
# This file is auto-generated by the update.sh script and will be wiped out by the update.sh script.
# Please don't edit this file.
#
# Build all test/push images:
#      docker buildx bake -f images/5.7/bake.hcl [test | push] --progressive plain [--load | --push]
# Build selected images:
#      docker buildx bake -f images/5.7/bake.hcl [target name, ...] --progressive plain [--load | --push]

#------------------------------------ test -----------------------------------

group "test" {
    targets=["enterprise_debian10_amd64", "community_debian10_amd64"]
}

target "enterprise_debian10_amd64" {
    tags=["aerospike/aerospike-server-enterprise-amd64:5.7.0.31", "aerospike/aerospike-server-enterprise-amd64:5.7"]
    platforms=["linux/amd64"]
    context="./images/5.7/enterprise/debian10"
}

target "community_debian10_amd64" {
    tags=["aerospike/aerospike-server-community-amd64:5.7.0.31", "aerospike/aerospike-server-community-amd64:5.7"]
    platforms=["linux/amd64"]
    context="./images/5.7/community/debian10"
}

#------------------------------------ push -----------------------------------

group "push" {
    targets=["enterprise_debian10", "community_debian10"]
}

target "enterprise_debian10" {
    tags=["aerospike/aerospike-server-enterprise:5.7.0.31", "aerospike/aerospike-server-enterprise:5.7.0.31_1", "aerospike/aerospike-server-enterprise:5.7"]
    platforms=["linux/amd64"]
    context="./images/5.7/enterprise/debian10"
}

target "community_debian10" {
    tags=["aerospike/aerospike-server:5.7.0.31", "aerospike/aerospike-server:5.7.0.31_1", "aerospike/aerospike-server:5.7"]
    platforms=["linux/amd64"]
    context="./images/5.7/community/debian10"
}

