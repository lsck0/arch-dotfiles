#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# "Don't turn off PC" mode: holds a systemd-inhibit lock against both sleep
# and idle, tracked via a PID file. hypridle respects dbus/systemd idle
# inhibitors by default (ignore_dbus_inhibit is unset in hypridle.conf), so
# this blocks the dim/lock/screen-off/suspend chain too, not just suspend.
PIDFILE="$TOGGLES_STATE_DIR/keep-awake.pid"

check() {
    if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo on
    else
        echo off
    fi
}

turn_on() {
    systemd-inhibit --what=sleep:idle --who=toggles --why="keep-awake toggle enabled" --mode=block sleep infinity &
    disown
    echo -n "$!" >"$PIDFILE"
}

turn_off() {
    [[ -f "$PIDFILE" ]] && kill "$(cat "$PIDFILE")" 2>/dev/null
    rm -f "$PIDFILE"
}

toggle_main keep-awake "Keep Awake" check turn_on turn_off "${1:-toggle}"
