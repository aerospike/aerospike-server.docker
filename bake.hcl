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
    targets=["enterprise_ubuntu24-04_amd64", "enterprise_ubuntu24-04_arm64", "federal_ubuntu24-04_amd64", "community_ubuntu24-04_amd64", "community_ubuntu24-04_arm64"]
}

target "enterprise_ubuntu24-04_amd64" {
    tags=["aerospike/aerospike-server-enterprise-amd64:8.0.0.8", "aerospike/aerospike-server-enterprise-amd64:latest"]
    platforms=["linux/amd64"]
    context="./enterprise/ubuntu24.04"
}

target "enterprise_ubuntu24-04_arm64" {
    tags=["aerospike/aerospike-server-enterprise-arm64:8.0.0.8", "aerospike/aerospike-server-enterprise-arm64:latest"]
    platforms=["linux/arm64"]
    context="./enterprise/ubuntu24.04"
}

target "federal_ubuntu24-04_amd64" {
    tags=["aerospike/aerospike-server-federal-amd64:8.0.0.8", "aerospike/aerospike-server-federal-amd64:latest"]
    platforms=["linux/amd64"]
    context="./federal/ubuntu24.04"
}

target "community_ubuntu24-04_amd64" {
    tags=["aerospike/aerospike-server-community-amd64:8.0.0.8", "aerospike/aerospike-server-community-amd64:latest"]
    platforms=["linux/amd64"]
    context="./community/ubuntu24.04"
}

target "community_ubuntu24-04_arm64" {
    tags=["aerospike/aerospike-server-community-arm64:8.0.0.8", "aerospike/aerospike-server-community-arm64:latest"]
    platforms=["linux/arm64"]
    context="./community/ubuntu24.04"
}

#------------------------------------ push -----------------------------------

group "push" {
    targets=["enterprise_ubuntu24-04", "federal_ubuntu24-04", "community_ubuntu24-04"]
}

target "enterprise_ubuntu24-04" {
    tags=["aerospike/aerospike-server-enterprise:8.0.0.8", "aerospike/aerospike-server-enterprise:8.0.0.8_1"]
    platforms=["linux/amd64,linux/arm64"]
    context="./enterprise/ubuntu24.04"
}

target "federal_ubuntu24-04" {
    tags=["aerospike/aerospike-server-federal:8.0.0.8", "aerospike/aerospike-server-federal:8.0.0.8_1"]
    platforms=["linux/amd64"]
    context="./federal/ubuntu24.04"
}

target "community_ubuntu24-04" {
    tags=["aerospike/aerospike-server:8.0.0.8", "aerospike/aerospike-server:8.0.0.8_1"]
    platforms=["linux/amd64,linux/arm64"]
    context="./community/ubuntu24.04"
}

