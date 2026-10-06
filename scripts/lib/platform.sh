# shellcheck shell=bash
# the platform file is the one source for HOSTNAME, FORM_FACTOR, PKG_GROUPS, EXTRA_PACKAGES, WIREGUARD and the optional
# LSCK0_SNAPSHOT=<YYYY-MM-DD> pin, else from the env: platforms/<hostname>.sh for luca's machines, platforms/local.sh
# (gitignored, written by bootstrap.sh) for a guest

# runtime copy for hyprland's platform.lua, which runs outside config.sh
PLATFORM_FORM_FACTOR_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/form-factor"

# platform_file <repo>: this machine's platform file, nothing for a machine without one
platform_file() {
    local file
    for file in "$1/platforms/$(</etc/hostname).sh" "$1/platforms/local.sh"; do
        [[ -f "$file" ]] && echo "$file" && return
    done
    return 0
}

# platform_groups_all <repo>: every module, a configs/<module>/ with a packages.txt
platform_groups_all() {
    find "$1/configs" -mindepth 2 -maxdepth 2 -name packages.txt -printf '%h\n' | sed 's#.*/##' | sort
}

# platform_form_factor <repo>: desktop, laptop, vm or wsl; the platform file's FORM_FACTOR, a probe only without one
platform_form_factor() {
    local file form_factor="${FORM_FACTOR:-}"
    file=$(platform_file "$1")
    if [[ -z "$form_factor" && -n "$file" ]]; then
        # shellcheck source=/dev/null
        form_factor=$(source "$file" && echo "${FORM_FACTOR:-}")
    fi
    if [[ -z "$form_factor" ]]; then
        if [[ "$(systemd-detect-virt 2>/dev/null)" == wsl ]]; then
            form_factor=wsl
        elif systemd-detect-virt -q; then
            form_factor=vm
        elif compgen -G '/sys/class/power_supply/BAT*' >/dev/null; then
            form_factor=laptop
        else
            form_factor=desktop
        fi
    fi
    case "$form_factor" in
    desktop | laptop | vm | wsl) echo "$form_factor" ;;
    *)
        echo "platform: FORM_FACTOR '${form_factor}' from ${file} is not one of desktop, laptop, vm, wsl" >&2
        return 1
        ;;
    esac
}

# platform_load <repo>: source the platform file, every group without one; exports FORM_FACTOR and LSCK0_SNAPSHOT
platform_load() {
    local file
    file=$(platform_file "$1")
    PKG_GROUPS=()
    if [[ -n "$file" ]]; then
        # shellcheck source=/dev/null
        source "$file"
        echo "platform: $file" >&2
    fi
    ((${#PKG_GROUPS[@]})) || mapfile -t PKG_GROUPS < <(platform_groups_all "$1")
    # a group that is not a discovered module is a typo or a dropped module, caught here not silently skipped
    local known grp
    known=" $(platform_groups_all "$1" | tr '\n' ' ') "
    for grp in "${PKG_GROUPS[@]}"; do
        [[ "$known" == *" $grp "* ]] || { echo "platform: PKG_GROUPS has '$grp', not a module in configs/" >&2; return 1; }
    done
    FORM_FACTOR=$(platform_form_factor "$1") || return 1
    # configs/base/pacman/link.sh runs as a child of install.sh
    export FORM_FACTOR LSCK0_SNAPSHOT
    mkdir -p "$(dirname "$PLATFORM_FORM_FACTOR_FILE")"
    echo "$FORM_FACTOR" >"$PLATFORM_FORM_FACTOR_FILE"
    echo "platform: form factor $FORM_FACTOR, groups ${PKG_GROUPS[*]}" >&2
}
