# shellcheck shell=bash
# the platform file is the one source of machine facts: HOSTNAME, FORM_FACTOR, PKG_GROUPS, EXTRA_PACKAGES, WIREGUARD,
# HOMELAB, SECURE_BOOT_OWN_KEYS and the optional LSCK0_SNAPSHOT=<YYYY-MM-DD> pin. platforms/<hostname>.sh for the owner's
# machines, PLATFORM_LOCAL (root-owned, written by bootstrap.sh) for any other; never a user fact

PLATFORM_LOCAL=/etc/dotfiles/platform.sh
# runtime copy for hyprland's platform.lua, which runs outside config.sh
PLATFORM_FORM_FACTOR_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/form-factor"
# exported to every module; each 1 or empty, WIREGUARD a secrets file name, FORM_FACTOR desktop, laptop, vm or wsl
PLATFORM_FACTS=(FORM_FACTOR HOMELAB WIREGUARD SECURE_BOOT_OWN_KEYS LSCK0_SNAPSHOT)

# platform_file <repo>: this machine's platform file, nothing for a machine without one. the machine's own answers win,
# so a new machine never picks up a platforms/ file that shares its hostname; a checkout's platforms/local.sh from
# before the system layer counts as them until system_copy moves it to PLATFORM_LOCAL, so both layers read the same
platform_file() {
    local file
    for file in "$PLATFORM_LOCAL" "$1/platforms/local.sh" "$1/platforms/$(</etc/hostname).sh"; do
        [[ -f "$file" ]] && echo "$file" && return
    done
    return 0
}

# platform_groups_all <repo>: every group, a configs/<group>/ with a packages.txt
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

# platform_load <repo>: source the platform file, every group without one; exports the facts, empty when unset
platform_load() {
    local file fact
    file=$(platform_file "$1")
    PKG_GROUPS=()
    EXTRA_PACKAGES=()
    if [[ -n "$file" ]]; then
        # shellcheck source=/dev/null
        source "$file"
        echo "platform: $file" >&2
    fi
    local all known grp
    mapfile -t all < <(platform_groups_all "$1")
    ((${#PKG_GROUPS[@]})) || PKG_GROUPS=("${all[@]}")
    # a group that is not a discovered module is a typo or a dropped module, caught here not silently skipped
    known=" ${all[*]} "
    for grp in "${PKG_GROUPS[@]}"; do
        [[ "$known" == *" $grp "* ]] || { echo "platform: PKG_GROUPS has '$grp', not a module in configs/" >&2; return 1; }
    done
    FORM_FACTOR=$(platform_form_factor "$1") || return 1
    for fact in "${PLATFORM_FACTS[@]}"; do
        export "$fact=${!fact:-}"
    done
    # root writes no file into a home
    if ((EUID != 0)); then
        mkdir -p "$(dirname "$PLATFORM_FORM_FACTOR_FILE")"
        echo "$FORM_FACTOR" >"$PLATFORM_FORM_FACTOR_FILE"
    fi
    echo "platform: form factor $FORM_FACTOR, groups ${PKG_GROUPS[*]}" >&2
}

# platform_packages <manifest>: the names in configs/<group>/<manifest>.txt over PKG_GROUPS, comments and blanks dropped
platform_packages() {
    local grp
    for grp in "${PKG_GROUPS[@]}"; do
        [[ -f "$DOTFILES/configs/$grp/$1.txt" ]] || continue
        sed -E 's/#.*//; s/[[:space:]]+$//' "$DOTFILES/configs/$grp/$1.txt" | awk 'NF'
    done
}
