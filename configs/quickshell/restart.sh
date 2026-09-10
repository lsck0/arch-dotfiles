#!/usr/bin/env bash
# Kill any existing instance before starting a fresh one — quickshell has no
# built-in single-instance guard, so repeated manual launches (e.g. while
# developing this config) silently stack duplicate bars/panels per screen.
#
# Kill the process GROUP, not just the process. Several widgets own
# long-lived helper processes — `wl-paste --watch` x2 (clipboard),
# `inotifywait -m` (plugin registry), `nmcli monitor` (network) — and
# quickshell does not reap them on exit, on SIGTERM or SIGKILL (verified
# both). The old `pkill -9 -f "^quickshell -p"` therefore orphaned five
# helpers on *every* restart, reparented to the user manager and invisible
# to the next pkill. Three stray inotifywait processes accumulated from
# three restarts in a single session before this was noticed. Children
# inherit quickshell's PGID, so `kill -- -PGID` takes the whole tree.
set -e

self_pgid=$(ps -o pgid= -p $$ | tr -d ' ')
hyprland_pid=$(pgrep -xo Hyprland || true)
hyprland_pgid=""
if [[ -n "$hyprland_pid" ]]; then
    hyprland_pgid=$(ps -o pgid= -p "$hyprland_pid" 2>/dev/null | tr -d ' ')
fi

for pid in $(pgrep -f "^quickshell -p" || true); do
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    # A Quickshell launched by Hyprland may initially share Hyprland's
    # process group. Never signal that group: doing so logs the user out.
    if [[ -n "$pgid" && "$pgid" != "$self_pgid" && "$pgid" != "$hyprland_pgid" ]]; then
        kill -9 -- "-$pgid" 2>/dev/null || true
    else
        kill -9 "$pid" 2>/dev/null || true
    fi
done

sleep 0.3
# Give Quickshell its own session/process group. Without setsid, a restart
# invoked from Hyprland inherits the compositor's group and group-killing the
# old bar also kills Hyprland.
exec setsid quickshell -p ~/.config/quickshell
