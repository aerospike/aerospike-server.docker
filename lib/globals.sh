# shellcheck shell=bash

export g_images_dir="images"
export g_target_dir="target"
export g_data_dir="data"
export g_data_template_dir="${g_data_dir}/template"
export g_data_scripts_dir="${g_data_dir}/scripts"
export g_data_res_dir="${g_data_dir}/res"
export g_data_config_dir="${g_data_dir}/config"

export g_all_editions=("enterprise" "federal" "community")

declare -A g_license=(
    [enterprise]="${g_data_res_dir}/ENTERPRISE_LICENSE"
    [federal]="${g_data_res_dir}/FEDERAL_LICENSE"
    [community]="${g_data_res_dir}/COMMUNITY_LICENSE")
export g_license
