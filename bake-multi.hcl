# Auto-generated bake file
group "test" { targets=["8-1_enterprise_ubi9_amd64", "8-1_enterprise_ubi9_arm64"] }
group "push" { targets=["8-1_enterprise_ubi9"] }

target "8-1_enterprise_ubi9_amd64" {
    tags=["aerospike/aerospike-server-enterprise:8.1.1.0-start-16-gea126d3-ubi9-amd64"]
    platforms=["linux/amd64"]
    context="./releases/8.1/enterprise/ubi9"
}
target "8-1_enterprise_ubi9_arm64" {
    tags=["aerospike/aerospike-server-enterprise:8.1.1.0-start-16-gea126d3-ubi9-arm64"]
    platforms=["linux/arm64"]
    context="./releases/8.1/enterprise/ubi9"
}

target "8-1_enterprise_ubi9" {
    tags=["aerospike/aerospike-server-enterprise:8.1.1.0-start-16-gea126d3", "aerospike/aerospike-server-enterprise:8.1.1.0-start-16-gea126d3-ubi9"]
    platforms=["linux/amd64", "linux/arm64"]
    context="./releases/8.1/enterprise/ubi9"
}

