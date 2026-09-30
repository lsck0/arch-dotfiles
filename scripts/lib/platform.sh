# shellcheck shell=bash
# platforms/<hostname>.sh decides package groups, boot features and mirror use. platform_load sources it
# and writes groups.conf and boot.conf, which install.sh and the link.sh scripts read; on a machine
# without a platform file those stay whatever install.sh asked for.

platform_load() { # repo dir
    local file
    file="$1/platforms/$(</etc/hostname).sh"
    [[ -f "$file" ]] || return 0
    # shellcheck source=/dev/null
    source "$file"
    printf '%s\n' "${PKG_GROUPS[@]}" >"$1/groups.conf"
    printf '%s\n' "${BOOT_FEATURES[@]}" >"$1/boot.conf"
    echo "platform: $file" >&2
}
