#!/usr/bin/env bash
# Generate Docker buildx bake HCL file for multi-arch builds.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/log.sh, lib/support.sh
# Expects: LINEAGES_TO_BUILD, G_VERSION_MAP, REGISTRY_PREFIXES, EDITION_FILTERS,
#          DISTRO_FILTERS, ARCH_FILTERS, BAKE_FILE (globals from docker-build.sh)

set -Eeuo pipefail

function generate_bake() {
    local build_ts="${1:-}"
    [ -z "${build_ts}" ] && build_ts=$(date -u +%Y%m%d%H%M%S 2>/dev/null || date +%Y%m%d%H%M%S)
    local test_targets="" push_targets=""
    local test_group="" push_group=""

    for lineage in "${LINEAGES_TO_BUILD[@]}"; do
        local version="${G_VERSION_MAP[${lineage}]}"
        local distros_building
        distros_building=$(support_distros_matching "${lineage}" "${DISTRO_FILTERS[*]:-}")
        local omit_distro_in_tag=0
        local num_distros
        num_distros=$(echo "${distros_building}" | wc -w)
        [ "${num_distros}" -eq 1 ] && omit_distro_in_tag=1

        # shellcheck disable=SC2086
        for edition in $(support_editions); do
            if [ ${#EDITION_FILTERS[@]} -gt 0 ]; then
                local match=false
                for ef in "${EDITION_FILTERS[@]}"; do
                    [ "${ef}" = "${edition}" ] && {
                        match=true
                        break
                    }
                done
                [ "${match}" = false ] && continue
            fi

            # shellcheck disable=SC2086
            for distro in ${distros_building}; do
                local ctx="./releases/${lineage}/${edition}/${distro}"
                [ ! -d "${ctx}" ] && continue

                local tag_base platforms
                tag_base="${lineage//./-}_${edition}_${distro//./-}"
                platforms=$(support_platforms_matching "${edition}" "${ARCH_FILTERS[*]:-}")
                [ -z "${platforms}" ] && continue
                local image_name="aerospike-server"
                [ "${edition}" != "community" ] && image_name+="-${edition}"
                local test_product="${REGISTRY_PREFIXES[0]}/${image_name}"

                # shellcheck disable=SC2086
                for plat in ${platforms}; do
                    local arch=${plat#*/}
                    local test_tag
                    if [ "${omit_distro_in_tag}" -eq 1 ]; then
                        test_tag="${test_product}:${version}-${arch}"
                    else
                        test_tag="${test_product}:${version}-${distro}-${arch}"
                    fi
                    test_group+="\"${tag_base}_${arch}\", "
                    test_targets+="target \"${tag_base}_${arch}\" {
    tags=[\"${test_tag}\"]
    platforms=[\"${plat}\"]
    context=\"${ctx}\"
}
"
                done

                local push_tags=""
                for reg in "${REGISTRY_PREFIXES[@]}"; do
                    local product="${reg}/${image_name}"
                    [ -n "${push_tags}" ] && push_tags+=", "
                    if [ "${omit_distro_in_tag}" -eq 1 ]; then
                        push_tags+="\"${product}:${lineage}\", \"${product}:${version}\", \"${product}:${version}-${build_ts}\""
                    else
                        push_tags+="\"${product}:${lineage}-${distro}\", \"${product}:${version}-${distro}\", \"${product}:${version}-${distro}-${build_ts}\""
                    fi
                done
                push_group+="\"${tag_base}\", "
                push_targets+="target \"${tag_base}\" {
    tags=[${push_tags}]
    platforms=[\"${platforms// /\", \"}\"]
    context=\"${ctx}\"
}
"
            done
        done
    done

    cat >"${BAKE_FILE}" <<EOF
# Auto-generated bake file
group "test" { targets=[${test_group%,*}] }
group "push" { targets=[${push_group%,*}] }

${test_targets}
${push_targets}
EOF
}
