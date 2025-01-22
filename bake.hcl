# This file contains the targets for the test images.
# This file is auto-generated by the update.sh script and will be wiped out by the update.sh script.
# Please don't edit this file.
#
# Build all test/push images:
#      docker buildx bake -f bake.hcl [test | push] --progressive plain [--load | --push]
# Build selected images:
#      docker buildx bake -f bake.hcl [target name, ...] --progressive plain [--load | --push]

#------------------------------------ test -----------------------------------

group "test" {
    targets=["enterprise_ubuntu20-04_amd64", "federal_ubuntu20-04_amd64", "community_ubuntu20-04_amd64"]
}

target "enterprise_ubuntu20-04_amd64" {
    tags=["aerospike/aerospike-server-enterprise-amd64:6.1.0.46", "aerospike/aerospike-server-enterprise-amd64:latest"]
    platforms=["linux/amd64"]
    context="./enterprise/ubuntu20.04"
}

target "federal_ubuntu20-04_amd64" {
    tags=["aerospike/aerospike-server-federal-amd64:6.1.0.46", "aerospike/aerospike-server-federal-amd64:latest"]
    platforms=["linux/amd64"]
    context="./federal/ubuntu20.04"
}

target "community_ubuntu20-04_amd64" {
    tags=["aerospike/aerospike-server-community-amd64:6.1.0.46", "aerospike/aerospike-server-community-amd64:latest"]
    platforms=["linux/amd64"]
    context="./community/ubuntu20.04"
}

#------------------------------------ push -----------------------------------

group "push" {
    targets=["enterprise_ubuntu20-04", "federal_ubuntu20-04", "community_ubuntu20-04"]
}

target "enterprise_ubuntu20-04" {
    tags=["aerospike/aerospike-server-enterprise:6.1.0.46", "aerospike/aerospike-server-enterprise:6.1.0.46_1"]
    platforms=["linux/amd64"]
    context="./enterprise/ubuntu20.04"
}

target "federal_ubuntu20-04" {
    tags=["aerospike/aerospike-server-federal:6.1.0.46", "aerospike/aerospike-server-federal:6.1.0.46_1"]
    platforms=["linux/amd64"]
    context="./federal/ubuntu20.04"
}

target "community_ubuntu20-04" {
    tags=["aerospike/aerospike-server:6.1.0.46", "aerospike/aerospike-server:6.1.0.46_1"]
    platforms=["linux/amd64"]
    context="./community/ubuntu20.04"
}

