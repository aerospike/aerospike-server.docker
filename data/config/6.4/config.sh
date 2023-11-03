# shellcheck shell=bash

export c_editions=("enterprise" "federal" "community")

export c_distros=("debian12" "el9")
export c_distro_default="debian12"
export c_distro_bases=("debian:bookworm-slim" "redhat/ubi9-minimal")

export c_archs=("x86_64" "aarch64")
export c_platforms=("linux/amd64" "linux/arm64")
