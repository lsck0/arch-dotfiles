#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2154
. "${profile}/profiledef.releng.sh"

iso_name="archlinux-lsck0"
iso_label="ARCH_LSCK0_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
kernel_params_x86_64="cow_spacesize=1G"
file_permissions+=(["/usr/local/bin/lsck0-install"]="0:0:755")
