#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# "Don't turn off PC" mode: holds a systemd-inhibit lock against both sleep and idle, tracked via a PID file.
PIDFILE="$TOGGLES_RUNTIME_DIR/keep-awake.pid"

# the recorded pid, only while it is still our inhibitor and not a reused pid
inhibitor_pid() {
    local pid
    [[ -f "$PIDFILE" ]] || return 1
    pid=$(<"$PIDFILE")
    [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == systemd-inhibit ]] && echo "$pid"
}

check() { inhibitor_pid >/dev/null && echo on || echo off; }

turn_on() {
    systemd-inhibit --what=sleep:idle --who=toggles --why="keep-awake toggle enabled" --mode=block sleep infinity &
    disown
    echo -n "$!" >"$PIDFILE"
}

turn_off() {
    local pid
    pid=$(inhibitor_pid) && kill "$pid" 2>/dev/null || true
    rm -f "$PIDFILE"
}

toggle_main keep-awake "Keep Awake" check turn_on turn_off "${1:-toggle}"
