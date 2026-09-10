#!/usr/bin/env bash
# Shared helpers for toggle-*.sh scripts: a tiny on/off value store plus a
# uniform CLI (get/label/on/off/toggle) so menu.sh and the status
# script can drive every toggle the same way regardless of what it does.

TOGGLES_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/toggles"
mkdir -p "$TOGGLES_STATE_DIR"

toggle_get() {
    cat "$TOGGLES_STATE_DIR/$1" 2>/dev/null || echo off
}

toggle_set() {
    echo -n "$2" >"$TOGGLES_STATE_DIR/$1"
}

# Volatile variant backed by tmpfs (XDG_RUNTIME_DIR), for a toggle whose
# check_fn has no live system state to query and must track its own status —
# use this instead of toggle_get/toggle_set when the underlying tool resets
# itself on boot (e.g. TLP always reverts to auto-detect). A persistent file
# would still say "on" after a reboot that silently cleared it; tmpfs gets
# wiped at the same time the real state does, so it can't go stale.
TOGGLES_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/toggles"
mkdir -p "$TOGGLES_RUNTIME_DIR"

toggle_get_volatile() {
    cat "$TOGGLES_RUNTIME_DIR/$1" 2>/dev/null || echo off
}

toggle_set_volatile() {
    echo -n "$2" >"$TOGGLES_RUNTIME_DIR/$1"
}

# notify-send, but never blocking. `org.freedesktop.Notifications` is owned by
# quickshell's own daemon (configs/quickshell/plugins/notifications/Service.qml).
# When quickshell isn't running, nothing owns that bus name and D-Bus falls back
# to activating plasma-workspace's `plasma_waitforname` handler, which sits and
# waits for the name to appear until the activation timeout (~25s). Without this
# wrapper every toggle on/off would hang for that long whenever the shell is
# down — which is exactly when you're most likely to be poking at toggles.
# (Before 2026-09-01 mako was D-Bus-activatable and always answered instantly;
# removing it is what exposed this.)
toggle_notify() {
    timeout 2 notify-send "$@" 2>/dev/null || true
}

# toggle_main <name> <label> <check_fn> <on_fn> <off_fn> <action>
# check_fn must echo "on" or "off" and take no arguments.
toggle_main() {
    local name=$1 label=$2 check_fn=$3 on_fn=$4 off_fn=$5 action=${6:-toggle}
    local current
    current=$("$check_fn")
    toggle_set "$name" "$current"

    case "$action" in
    get)
        echo "$current"
        ;;
    label)
        if [[ "$current" == on ]]; then echo "● $label (on)"; else echo "○ $label (off)"; fi
        ;;
    on)
        "$on_fn"
        toggle_set "$name" on
        toggle_notify -a Toggles "$label" "Turned on"
        ;;
    off)
        "$off_fn"
        toggle_set "$name" off
        toggle_notify -a Toggles "$label" "Turned off"
        ;;
    toggle)
        if [[ "$current" == on ]]; then
            "$off_fn"
            toggle_set "$name" off
            toggle_notify -a Toggles "$label" "Turned off"
        else
            "$on_fn"
            toggle_set "$name" on
            toggle_notify -a Toggles "$label" "Turned on"
        fi
        ;;
    *)
        echo "usage: $(basename "$0") {get|label|on|off|toggle}" >&2
        exit 1
        ;;
    esac
}
