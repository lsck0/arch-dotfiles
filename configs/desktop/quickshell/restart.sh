#!/usr/bin/env bash
# kill whole process groups, quickshell does not reap its helper children
set -e

config="${HOME}/.config/quickshell"
self_pgid=$(ps -o pgid= -p $$ | tr -d ' ')
hyprland_pid=$(pgrep -xo Hyprland || true)
hyprland_pgid=""
if [[ -n "$hyprland_pid" ]]; then
    hyprland_pgid=$(ps -o pgid= -p "$hyprland_pid" 2>/dev/null | tr -d ' ')
fi

# only this user's instance of this config, not ipc clients or other instances
for pid in $(pgrep -u "$USER" -f "^([^ ]*/)?(quickshell|qs)( -[^ ]+)* -p ${config}( |\$)" || true); do
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    # one launched by hyprland may share its process group
    if [[ -n "$pgid" && "$pgid" != "$self_pgid" && "$pgid" != "$hyprland_pgid" ]]; then
        kill -9 -- "-$pgid" 2>/dev/null || true
    else
        kill -9 "$pid" 2>/dev/null || true
    fi
done

sleep 0.3
# own process group so the next restart can kill it
exec setsid quickshell -p "$config"
