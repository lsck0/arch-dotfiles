#!/usr/bin/env bash
# run.sh [args...]: ani-cli inside the protonvpn namespace as the user who called sudo. root only for the namespace
# switch; the app runs with that user's ids and no privileges. sudoers allows exactly this file, it only ever execs
# /usr/bin/ani-cli, so the arguments reach nothing but ani-cli itself
set -euo pipefail

NS=protonvpn
IFACE=wg-protonvpn
APP=/usr/bin/ani-cli

user=${SUDO_USER:?run through sudo}
uid=$(id -u "$user")
gid=$(id -g "$user")
# fail closed: no namespace or tunnel, no start; the app never falls back onto the real link
if ! ip -n "$NS" link show "$IFACE" >/dev/null 2>&1; then
    echo "protonvpn-netns: namespace '$NS' is down (systemctl status protonvpn-netns), not starting $APP" >&2
    exit 1
fi

# only names, never paths or options, from the caller's environment (sudoers env_keep)
plain() { [[ "${!1:-}" =~ ^[A-Za-z0-9_.:@-]*$ ]] && printf '%s' "${!1:-}"; }
exec ip netns exec "$NS" setpriv --reuid="$uid" --regid="$gid" --init-groups --inh-caps=-all --bounding-set=-all \
    env -i \
    HOME="$(getent passwd "$user" | cut -d: -f6)" USER="$user" LOGNAME="$user" \
    PATH=/usr/local/bin:/usr/bin \
    XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    WAYLAND_DISPLAY="$(plain WAYLAND_DISPLAY)" DISPLAY="$(plain DISPLAY)" \
    TERM="$(plain TERM)" COLORTERM="$(plain COLORTERM)" LANG="$(plain LANG)" \
    "$APP" "$@"
