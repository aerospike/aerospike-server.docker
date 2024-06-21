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
    targets=["enterprise_ubuntu22-04_amd64", "enterprise_ubuntu22-04_arm64", "federal_ubuntu22-04_amd64", "community_ubuntu22-04_amd64", "community_ubuntu22-04_arm64"]
}

target "enterprise_ubuntu22-04_amd64" {
    tags=["aerospike/aerospike-server-enterprise-amd64:7.1.0.2", "aerospike/aerospike-server-enterprise-amd64:latest"]
    platforms=["linux/amd64"]
    context="./enterprise/ubuntu22.04"
}

target "enterprise_ubuntu22-04_arm64" {
    tags=["aerospike/aerospike-server-enterprise-arm64:7.1.0.2", "aerospike/aerospike-server-enterprise-arm64:latest"]
    platforms=["linux/arm64"]
    context="./enterprise/ubuntu22.04"
}

target "federal_ubuntu22-04_amd64" {
    tags=["aerospike/aerospike-server-federal-amd64:7.1.0.2", "aerospike/aerospike-server-federal-amd64:latest"]
    platforms=["linux/amd64"]
    context="./federal/ubuntu22.04"
}

target "community_ubuntu22-04_amd64" {
    tags=["aerospike/aerospike-server-community-amd64:7.1.0.2", "aerospike/aerospike-server-community-amd64:latest"]
    platforms=["linux/amd64"]
    context="./community/ubuntu22.04"
}

target "community_ubuntu22-04_arm64" {
    tags=["aerospike/aerospike-server-community-arm64:7.1.0.2", "aerospike/aerospike-server-community-arm64:latest"]
    platforms=["linux/arm64"]
    context="./community/ubuntu22.04"
}

#------------------------------------ push -----------------------------------

group "push" {
    targets=["enterprise_ubuntu22-04", "federal_ubuntu22-04", "community_ubuntu22-04"]
}

target "enterprise_ubuntu22-04" {
    tags=["aerospike/aerospike-server-enterprise:7.1.0.2", "aerospike/aerospike-server-enterprise:7.1.0.2_1", "aerospike/aerospike-server-enterprise:latest"]
    platforms=["linux/amd64,linux/arm64"]
    context="./enterprise/ubuntu22.04"
}

target "federal_ubuntu22-04" {
    tags=["aerospike/aerospike-server-federal:7.1.0.2", "aerospike/aerospike-server-federal:7.1.0.2_1", "aerospike/aerospike-server-federal:latest"]
    platforms=["linux/amd64"]
    context="./federal/ubuntu22.04"
}

target "community_ubuntu22-04" {
    tags=["aerospike/aerospike-server:7.1.0.2", "aerospike/aerospike-server:7.1.0.2_1", "aerospike/aerospike-server:latest"]
    platforms=["linux/amd64,linux/arm64"]
    context="./community/ubuntu22.04"
}

