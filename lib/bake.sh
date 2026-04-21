#!/usr/bin/env bash
# Generate Docker buildx bake HCL file for multi-arch builds.
# Copyright 2014-2025 Aerospike, Inc. Licensed under Apache-2.0. See LICENSE.
# Dependencies: lib/log.sh, lib/support.sh, lib/version.sh (find_latest_version_for_lineage)
# Expects: LINEAGES_TO_BUILD, G_VERSION_MAP, REGISTRY_PREFIXES, EDITION_FILTERS,
#          DISTRO_FILTERS, ARCH_FILTERS, BAKE_FILE (globals from docker-build.sh)
# Optional env: BAKE_TAG_LATEST_AUTO (default 0), BAKE_TAG_LATEST_FORCE (default 0),
#                BAKE_IMMUTABLE_REVISION (optional; adds version_N tags, e.g. 8.1.2.0_1)

set -Eeuo pipefail

# Highest semver among latest GA per support lineage — for :latest bake tags when the build matches.
function find_latest_version_among_support_releases() {
    local lg v
    local -a vers=()
    # shellcheck disable=SC2046
    for lg in $(support_releases); do
        v=$(find_latest_version_for_lineage "${lg}")
        [ -n "${v}" ] && vers+=("${v}")
    done
    [ ${#vers[@]} -eq 0 ] && {
        echo ""
        return
    }
    printf '%s\n' "${vers[@]}" | sort -V | tail -1
}

function generate_bake() {
    local build_ts="${1:-}"
    [ -z "${build_ts}" ] && build_ts=$(date -u +%Y%m%d%H%M%S 2>/dev/null || date +%Y%m%d%H%M%S)
    local test_targets="" push_targets=""
    local test_group="" push_group=""

    local rev_suffix=""
    if [ -n "${BAKE_IMMUTABLE_REVISION:-}" ]; then
        rev_suffix="_${BAKE_IMMUTABLE_REVISION}"
    fi

    local overall_latest=""
    if [ "${BAKE_TAG_LATEST_FORCE:-0}" != "1" ] && [ "${BAKE_TAG_LATEST_AUTO:-0}" = "1" ]; then
        overall_latest=$(find_latest_version_among_support_releases 2>/dev/null || true)
        if [ -n "${overall_latest}" ]; then
            log_info "Latest GA across support lineages (for optional :latest tags when build matches): ${overall_latest}"
        fi
    fi

    for lineage in "${LINEAGES_TO_BUILD[@]}"; do
        local version="${G_VERSION_MAP[${lineage}]}"
        local include_latest=0
        if [ "${BAKE_TAG_LATEST_FORCE:-0}" = "1" ]; then
            include_latest=1
        elif [ "${BAKE_TAG_LATEST_AUTO:-0}" = "1" ] && [ -n "${overall_latest}" ] && [ "${version}" = "${overall_latest}" ]; then
            include_latest=1
        fi

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

                local distro_slug=${distro//./-}
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
                    local test_tag test_tags_line
                    if [ "${omit_distro_in_tag}" -eq 1 ]; then
                        test_tag="${test_product}:${version}-${arch}"
                    else
                        test_tag="${test_product}:${version}-${distro}-${arch}"
                    fi
                    test_tags_line="\"${test_tag}\""
                    if [ -n "${rev_suffix}" ]; then
                        if [ "${omit_distro_in_tag}" -eq 1 ]; then
                            test_tags_line+=", \"${test_product}:${version}${rev_suffix}-${arch}\""
                        else
                            test_tags_line+=", \"${test_product}:${version}-${distro}${rev_suffix}-${arch}\""
                        fi
                    fi
                    if [ "${include_latest}" -eq 1 ]; then
                        if [ "${omit_distro_in_tag}" -eq 1 ]; then
                            test_tags_line+=", \"${test_product}:latest-${arch}\""
                        else
                            test_tags_line+=", \"${test_product}:latest-${distro_slug}-${arch}\""
                        fi
                    fi
                    test_group+="\"${tag_base}_${arch}\", "
                    test_targets+="target \"${tag_base}_${arch}\" {
    tags=[${test_tags_line}]
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
                        [ -n "${rev_suffix}" ] && push_tags+=", \"${product}:${version}${rev_suffix}\""
                        [ "${include_latest}" -eq 1 ] && push_tags+=", \"${product}:latest\""
                    else
                        push_tags+="\"${product}:${lineage}-${distro}\", \"${product}:${version}-${distro}\", \"${product}:${version}-${distro}-${build_ts}\""
                        [ -n "${rev_suffix}" ] && push_tags+=", \"${product}:${version}-${distro}${rev_suffix}\""
                        [ "${include_latest}" -eq 1 ] && push_tags+=", \"${product}:latest-${distro_slug}\""
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
