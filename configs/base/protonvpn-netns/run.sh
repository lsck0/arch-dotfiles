#!/bin/sh
# sudo target (NOPASSWD for wheel): run <command> [args...] in the protonvpn namespace as the sudo caller, never as
# root. sh, not nu: nu evaluates a --flag=(expr) argument of a script before its main runs, here as root, and requotes
# flag values; "$@" reaches the command untouched (run.test.nu).
set -eu

NS=protonvpn
IFACE=wg-protonvpn

fail() {
    printf 'protonvpn-netns: %s\n' "$2" >&2
    exit "$1"
}

# sudoers env_keep passes these; a value is kept only as plain text, never a path or an option
plain() {
    case $1 in
        *[!A-Za-z0-9_.:@-]*) ;;
        *) printf %s "$1" ;;
    esac
}

user=${SUDO_USER:-}
[ -n "$user" ] || fail 1 "run through sudo"
[ $# -gt 0 ] || fail 2 "usage: run <command> [args...]"
uid=$(id -u "$user")
gid=$(id -g "$user")
# fail closed: never fall back onto the real link
ip -n "$NS" link show "$IFACE" > /dev/null 2>&1 ||
    fail 1 "namespace '$NS' is down (systemctl status protonvpn-netns), not starting $1"
home=$(getent passwd "$user" | cut -d: -f6)

exec ip netns exec "$NS" setpriv --reuid="$uid" --regid="$gid" --init-groups --inh-caps=-all --bounding-set=-all \
    env -i "HOME=$home" "USER=$user" "LOGNAME=$user" PATH=/usr/local/bin:/usr/bin \
    "XDG_RUNTIME_DIR=/run/user/$uid" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus" \
    "WAYLAND_DISPLAY=$(plain "${WAYLAND_DISPLAY:-}")" "DISPLAY=$(plain "${DISPLAY:-}")" \
    "TERM=$(plain "${TERM:-}")" "COLORTERM=$(plain "${COLORTERM:-}")" "LANG=$(plain "${LANG:-}")" \
    "$@"
