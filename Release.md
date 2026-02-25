# Release Notes — Docker Build System Restructure

Complete restructuring of the Docker image build system to support multiple release lineages (7.1, 7.2, 8.0, 8.1+), multiple editions (community, enterprise, federal), and multiple base images (Ubuntu, Red Hat UBI) with a unified, streamlined workflow.

## Motivation

The previous build system had separate directories for each edition with duplicated Dockerfiles and configuration. This made maintenance difficult and didn't scale well for supporting multiple release versions simultaneously. The new system uses a single script that generates all necessary Dockerfiles dynamically.

## Changes

### New Build System

- **docker-build.sh** – Unified script that replaces both update.sh and build.sh
  - Generates Dockerfiles dynamically based on release lineage
  - Fetches version info and checksums from artifacts server
  - Supports custom artifact URLs for staging/testing
  - Builds using Docker Buildx Bake for efficient multi-architecture builds
  - Three modes: `-t` (test/local), `-p` (push to registry), `-g` (generate only)
  - Filter support: `-e` for editions, `-d` for distros (supports multiple values)

- **test.sh** – Updated functional test script
  - Test images from releases/ directory or specific image tags (`-i`)
  - Platform selection (`-p linux/amd64` or `linux/arm64`)
  - Edition verification with mismatch warnings
  - Comprehensive tests: container startup, asd process, asinfo, version, edition, namespace

### New Directory Structure

```
releases/<lineage>/<edition>/<distro>/
  ├── Dockerfile
  ├── entrypoint.sh
  ├── install.sh          # Copied from scripts/deb or scripts/rpm at generate time
  └── aerospike.template.conf
```

Example: `releases/8.1/enterprise/ubuntu24.04/`

### Supported Matrix

| Lineage | Distros | Editions |
|---------|---------|----------|
| 7.1 | ubuntu22.04, ubi9 | community, enterprise, federal |
| 7.2 | ubuntu24.04, ubi9 | community, enterprise, federal |
| 8.0 | ubuntu24.04, ubi9 | community, enterprise, federal |
| 8.1+ | ubuntu24.04, ubi9, ubi10 | community, enterprise, federal |

(ubi10 for 8.1+ is optional; use `-d ubi10` to include it.)

### Version Format Support

- Release: `8.1.1.0`
- Release candidate: `8.1.1.0-rc2`
- Development: `8.1.1.0-start-16`
- Development with git hash: `8.1.1.0-start-16-gea126d3`

### Library Modules (lib/)

- **support.sh** – Release/distro/edition support matrix and mappings
- **version.sh** – Version lookup and package URL generation
- **fetch.sh** – HTTP fetch helper with debugging support
- **log.sh** – Colored logging functions

### Install Scripts (scripts/)

- **deb/install.sh** – Ubuntu/Debian installation (uses apt-get, dpkg)
- **rpm/install.sh** – RHEL/UBI installation (uses microdnf, rpm)
- Fixed curl conflict with pre-installed curl-minimal in UBI images

### Files Removed

- build.sh – Replaced by docker-build.sh
- update.sh – Replaced by docker-build.sh
- bake.hcl – Replaced by auto-generated bake-multi.hcl
- community/, enterprise/, federal/ – Old static directories replaced by dynamic releases/
- releases.yaml – No longer needed
- docs/build.md – Outdated documentation
- res/eval_features.conf – Moved to config/
- lib/verbose_call.sh – Unused
- template/0/Dockerfile.template, template/0/README.md, template/0/aerospike.template.conf – Unused

### Files Reorganized

- licenses/COMMUNITY_LICENSE – Moved from community/COMMUNITY_LICENSE
- licenses/ENTERPRISE_LICENSE – Moved from enterprise/ENTERPRISE_LICENSE
- licenses/FEDERAL_LICENSE – Moved from federal/FEDERAL_LICENSE
- config/eval_features.conf – Moved from res/eval_features.conf

### Final Clean Structure

```
aerospike-server.docker/
├── docker-build.sh              # Main build script (generate + build)
├── test.sh                      # Functional test script
├── lib/
│   ├── fetch.sh                 # HTTP fetch helper
│   ├── log.sh                   # Colored logging functions
│   ├── support.sh               # Release/distro/edition support matrix
│   └── version.sh               # Version lookup and URL generation
├── scripts/
│   ├── deb/
│   │   └── install.sh           # Ubuntu/Debian install script
│   └── rpm/
│       └── install.sh           # RHEL/UBI install script
├── template/
│   ├── 0/
│   │   └── entrypoint.sh        # Container entrypoint script
│   └── 7/
│       └── aerospike.template.conf  # Aerospike config template
├── config/
│   └── eval_features.conf       # Sample evaluation feature key
├── licenses/
│   ├── COMMUNITY_LICENSE        # Apache 2.0 license
│   ├── ENTERPRISE_LICENSE       # Enterprise license info
│   └── FEDERAL_LICENSE          # Federal license info
├── releases/                    # Generated Dockerfiles (gitignore recommended)
├── bake-multi.hcl               # Generated bake file (gitignore recommended)
├── README.md                    # Main documentation
├── README-short.txt             # Docker Hub short description
└── logo.png                     # Aerospike logo
```

### Documentation

Updated README.md with:

- New "Building Images" section with prerequisites, examples, and workflow
- Updated "Image Versions" section with base image and distro support tables
- Fixed typos and broken links

### Usage Examples

```bash
# Build all editions/distros for lineage 8.1 (local test)
./docker-build.sh -t 8.1

# Build specific edition and distro
./docker-build.sh -t 8.1 -e enterprise -d ubuntu24.04

# Build multiple editions and distros
./docker-build.sh -t 8.1 -e enterprise community -d ubuntu24.04 ubi9

# Build from staging server
./docker-build.sh -t 8.1.1.0-start-108 -e enterprise \
   -u https://stage.aerospike.com/artifacts/docker/aerospike-server-enterprise

# Generate Dockerfiles only
./docker-build.sh -g 8.1

# Test specific image
./test.sh -i aerospike/aerospike-server-enterprise:8.1.1.0

# Test built images
./test.sh 8.1 -e enterprise -d ubuntu24.04
```

### Testing

- All bash scripts pass syntax validation (`bash -n`)
- Trailing whitespace removed from all scripts
- Install scripts tested on Ubuntu 24.04 and UBI 9

---

## Recent Changes

- **Local artifacts directory**  
  `-u` can point to a local directory (e.g. `./artifacts` or `artifacts`). The script resolves relative paths against the repo root, detects server packages by edition/version/arch (exact and glob), and when found uses native `.deb`/`.rpm` with `COPY` into the image (no download). Sets `AEROSPIKE_LOCAL_PKG=1`. Enables building from local packages without an artifacts server.

- **Native package fallback**  
  When a tgz bundle is not found on the artifacts server, the build system falls back to native `.rpm` (el9/el10) or `.deb` (Ubuntu) from the same or configured server (e.g. JFrog Artifactory). Images can be built from either tgz bundles or native packages.

- **Optional ubi10 for 8.1+**  
  Distro `ubi10` is supported for lineage 8.1+ (base image `ubi10/ubi-minimal:10.0`, artifact name `el10`). Not included in the default distro list; use `-d ubi10` to build UBI 10 images.

- **Multiple registries in push mode**  
  Push mode supports multiple `-r` registries (e.g. `-r reg1 -r reg2`). Each registry receives the same set of tags (lineage, version, version-timestamp, version-distro).

- **Generated `install.sh` in releases/**  
  Each generated `releases/<lineage>/<edition>/<distro>/` directory now includes `install.sh`, copied from `scripts/deb/install.sh` or `scripts/rpm/install.sh` at generate time. When using a local artifacts dir, server packages (`server_amd64.deb`/`server_arm64.deb` or `server_x86_64.rpm`/`server_aarch64.rpm`) are also copied into the build context.

- **Build without tools**  
  When no tools version is found for a given version/lineage, the build continues using native `.rpm`/`.deb` only (server package, no tools from tgz). A warning is printed.

- **Distro prefix match**  
  The `-d` filter supports prefix matching (e.g. `-d ubuntu` for all Ubuntu distros, `-d ubi` for all UBI).

- **.gitignore**  
  Generated files ignored: `bake-multi.hcl`, `.DS_Store`. The `releases/` directory is not in `.gitignore` in the current layout; it can be committed (e.g. for 7.1) or ignored depending on workflow.

- **CI workflows**  
  `.github/workflows/build.yml` still references `update.sh` and `build.sh`. These should be updated to use `docker-build.sh` (e.g. generate with `./docker-build.sh -g` for the "no diff" check, and `./docker-build.sh -t` for build/test) to align with the new build system.
