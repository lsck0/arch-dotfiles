# shellcheck shell=bash
# user path units that wait for an app to appear: link.sh owns when one exists, a one-shot hook script retires itself.
# the units are rendered from the call, not shipped, so the five app hooks share one shape instead of near-identical files

USER_HOOK_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

# user_hook <name> --watch <path...> [--mkdir] [--permanent] [--no-brake]: render <name>.path + <name>.service into the
# user unit dir, arm the path and run the service once now. --watch lists the paths whose change runs the hook; --mkdir
# has the path unit make a missing watch dir. the brake (StartLimit) is on by default because an app rewriting a watched
# path in bursts (syncthing into ~/sync, a self-updating client) would otherwise retrigger in a loop; --no-brake for a
# path written once. --permanent keeps the service enabled at login too, so an event missed while logged out still
# applies, else the hook retires once done. ExecStart is %h-relative to $PWD/hook/<name>.sh, the hook script in the checkout
user_hook() {
    local name="$1" makedir="" permanent="" brake=1 execstart
    local -a watch=()
    shift
    while (($#)); do
        case "$1" in
            --watch) shift; while (($#)) && [[ "$1" != --* ]]; do watch+=("$1"); shift; done ;;
            --mkdir) makedir=1; shift ;;
            --permanent) permanent=1; shift ;;
            --no-brake) brake=0; shift ;;
            *) echo "user_hook: unknown argument '$1'" >&2; return 1 ;;
        esac
    done
    execstart="%h/${PWD#"$HOME"/}/hook/${name}.sh"
    mkdir -p "$USER_HOOK_UNIT_DIR"
    rm -f "${USER_HOOK_UNIT_DIR}/${name}.path" "${USER_HOOK_UNIT_DIR}/${name}.service"
    {
        printf '[Unit]\nDescription=watch for the %s hook\n\n[Path]\n' "$name"
        printf 'PathChanged=%s\n' "${watch[@]}"
        [[ -n "$makedir" ]] && printf 'MakeDirectory=yes\n'
        printf '\n[Install]\nWantedBy=default.target\n'
    } >"${USER_HOOK_UNIT_DIR}/${name}.path"
    {
        printf '[Unit]\nDescription=run the %s hook\n' "$name"
        ((brake)) && printf 'StartLimitIntervalSec=1min\nStartLimitBurst=20\n'
        printf '\n[Service]\nType=oneshot\nExecStart=%s\n' "$execstart"
        [[ -n "$permanent" ]] && printf '\n[Install]\nWantedBy=default.target\n'
    } >"${USER_HOOK_UNIT_DIR}/${name}.service"
    systemctl --user daemon-reload
    systemctl --user enable --now "${name}.path"
    systemctl --user start --no-block "${name}.service"
    # permanent hooks also run at login (their [Install]); a retiring one's service is reached only through the path
    [[ -n "$permanent" ]] && systemctl --user enable "${name}.service"
    return 0
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

# user_hook_oneshot <name> <done check> --watch <path...> [flags]: retire the hook once the check passes, else render
# and arm it (user_hook's flags follow the check)
user_hook_oneshot() {
    local name="$1" check="$2"
    shift 2
    if "$check"; then
        user_hook_retire "$name"
    else
        user_hook "$name" "$@"
    fi
}
