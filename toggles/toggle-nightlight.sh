#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Blue-light filter, via hyprsunset.
#
# hyprsunset was installed and bound to SHIFT+brightness for raw gamma
# nudges, but **nothing ever started the daemon** — so those two keybinds
# have been failing silently (`Couldn't connect to ....hyprsunset.sock`)
# for as long as they have existed. This toggle starts it on demand, and
# hyprland_autostart.lua now starts it at login so the gamma binds work too.
#
# `off` deliberately does NOT kill the daemon, it returns the temperature to
# neutral. Killing it would re-break those gamma keybinds, and an idle
# hyprsunset costs nothing.

DAY=6000     # hyprsunset's own neutral default
NIGHT=4000   # warm without being orange; adjust with `set <kelvin>`

running() { pgrep -x hyprsunset >/dev/null 2>&1; }

ensure_daemon() {
    running && return 0
    setsid hyprsunset -t "$DAY" >/dev/null 2>&1 &
    # The socket appears a moment after the process does; without this the
    # first `hyprctl hyprsunset` after a cold start races it and fails.
    for _ in $(seq 1 20); do
        hyprctl hyprsunset temperature >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    return 0
}

temperature() {
    running || { echo "$DAY"; return; }
    hyprctl hyprsunset temperature 2>/dev/null | tr -dc '0-9' || echo "$DAY"
}

# On means "warmer than neutral", not "daemon alive" — the daemon is alive
# whenever the session is.
check() {
    local t
    t=$(temperature)
    [[ -n "$t" && "$t" -lt "$DAY" ]] && echo on || echo off
}

turn_on() {
    ensure_daemon
    hyprctl hyprsunset temperature "$NIGHT" >/dev/null 2>&1 || true
}

turn_off() {
    running || return 0
    hyprctl hyprsunset temperature "$DAY" >/dev/null 2>&1 || true
}

case "${1:-toggle}" in
set)
    [[ ${2:-} =~ ^[0-9]+$ ]] || { echo "usage: $(basename "$0") set <kelvin>" >&2; exit 1; }
    ensure_daemon
    hyprctl hyprsunset temperature "$2" >/dev/null 2>&1 || true
    toggle_set nightlight "$([[ $2 -lt $DAY ]] && echo on || echo off)"
    toggle_notify -a Toggles "Night Light" "${2}K"
    ;;
temperature) temperature ;;
*)
    toggle_main nightlight "Night Light" check turn_on turn_off "${1:-toggle}"
    ;;
esac
