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
    targets=["enterprise_debian11_amd64", "enterprise_debian11_arm64", "federal_debian11_amd64", "community_debian11_amd64", "community_debian11_arm64"]
}

target "enterprise_debian11_amd64" {
    tags=["aerospike/aerospike-server-enterprise-amd64:6.2.0.26", "aerospike/aerospike-server-enterprise-amd64:latest"]
    platforms=["linux/amd64"]
    context="./enterprise/debian11"
}

target "enterprise_debian11_arm64" {
    tags=["aerospike/aerospike-server-enterprise-arm64:6.2.0.26", "aerospike/aerospike-server-enterprise-arm64:latest"]
    platforms=["linux/arm64"]
    context="./enterprise/debian11"
}

target "federal_debian11_amd64" {
    tags=["aerospike/aerospike-server-federal-amd64:6.2.0.26", "aerospike/aerospike-server-federal-amd64:latest"]
    platforms=["linux/amd64"]
    context="./federal/debian11"
}

target "community_debian11_amd64" {
    tags=["aerospike/aerospike-server-community-amd64:6.2.0.26", "aerospike/aerospike-server-community-amd64:latest"]
    platforms=["linux/amd64"]
    context="./community/debian11"
}

target "community_debian11_arm64" {
    tags=["aerospike/aerospike-server-community-arm64:6.2.0.26", "aerospike/aerospike-server-community-arm64:latest"]
    platforms=["linux/arm64"]
    context="./community/debian11"
}

#------------------------------------ push -----------------------------------

group "push" {
    targets=["enterprise_debian11", "federal_debian11", "community_debian11"]
}

target "enterprise_debian11" {
    tags=["aerospike/aerospike-server-enterprise:6.2.0.26", "aerospike/aerospike-server-enterprise:6.2.0.26_2"]
    platforms=["linux/amd64,linux/arm64"]
    context="./enterprise/debian11"
}

target "federal_debian11" {
    tags=["aerospike/aerospike-server-federal:6.2.0.26", "aerospike/aerospike-server-federal:6.2.0.26_2"]
    platforms=["linux/amd64"]
    context="./federal/debian11"
}

target "community_debian11" {
    tags=["aerospike/aerospike-server:6.2.0.26", "aerospike/aerospike-server:6.2.0.26_2"]
    platforms=["linux/amd64,linux/arm64"]
    context="./community/debian11"
}

