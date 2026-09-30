# shellcheck shell=bash
# platform_load <repo>: platforms/<hostname>.sh decides groups.conf and boot.conf

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
