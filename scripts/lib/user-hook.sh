# shellcheck shell=bash
# user path units that wait for an app to appear: link.sh owns when one exists, a one-shot hook script retires itself

USER_HOOK_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

# user_hook_install <hook dir> <name>: install <name>.path + <name>.service as user units, arm the path, run once now
# (unit_install is module.sh's; a hook script sourcing this file alone only retires)
user_hook_install() {
    local dir="$1" name="$2"
    unit_install "${dir}/${name}.path" "${dir}/${name}.service"
    systemctl --user enable --now "${name}.path"
    systemctl --user start --no-block "${name}.service"
}

# user_hook_retire <name>: the hook's work is done, drop its units; a no-op once they are gone
user_hook_retire() {
    local name="$1"
    [[ -e "${USER_HOOK_UNIT_DIR}/${name}.path" || -e "${USER_HOOK_UNIT_DIR}/${name}.service" ]] || return 0
    # no user bus outside a session: the files still go, the manager drops the units on its next reload
    systemctl --user disable --now "${name}.path" 2>/dev/null || true
    rm -f "${USER_HOOK_UNIT_DIR}/${name}.path" "${USER_HOOK_UNIT_DIR}/${name}.service" \
        "${USER_HOOK_UNIT_DIR}/default.target.wants/${name}.path"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "user-hook: retired ${name}" >&2
}

# user_hook_oneshot <hook dir> <name> <done check...>: retire the hook once the check passes, else install it
user_hook_oneshot() {
    local dir="$1" name="$2"
    shift 2
    if "$@"; then
        user_hook_retire "$name"
    else
        user_hook_install "$dir" "$name"
    fi
}
