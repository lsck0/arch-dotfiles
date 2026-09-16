#!/usr/bin/env bash
# Applies a monitor scale change at runtime, keeping the connector's current
# mode and position untouched.
#
# WHY THIS EXISTS. Display.qml's scale buttons used to run
# `hyprctl keyword monitor <name>,preferred,auto,<scale>` directly. On this
# Hyprland version that fails outright — `hyprctl keyword` refuses to run
# under the non-legacy (Lua) config parser this setup uses
# (configs/hyprland/*.lua, loaded via hl.monitor(...) — see
# hyprland_monitors.lua), printing "keyword can't work with non-legacy
# parsers" and changing nothing. That is the actual "buttons don't work"
# bug: every click silently no-opped.
#
# The working runtime equivalent is `hyprctl eval` executing the same Lua
# `hl.monitor({...})` table constructor the static config uses. But
# `preferred,auto` (letting Hyprland re-pick mode/position) is also the
# wrong instinct here: this setup pins an explicit mode+position per output
# (hyprland_monitors.lua) specifically to keep the two identical 4K panels
# both at their max 144Hz mode and in their configured left/right layout;
# `preferred` can silently downgrade the refresh rate or shuffle position on
# some GPU/driver combinations. So this reads the monitor's CURRENT mode and
# position back from `hyprctl monitors -j` and only changes scale, which is
# the one property the buttons are actually for.
set -uo pipefail

name="${1:?usage: set-monitor-scale.sh <output-name> <scale>}"
scale="${2:?usage: set-monitor-scale.sh <output-name> <scale>}"

mon=$(hyprctl -j monitors | jq -c --arg n "$name" '.[] | select(.name == $n)') || exit 1
[[ -n "$mon" ]] || { echo "no such monitor: $name" >&2; exit 1; }

w=$(jq -r '.width' <<<"$mon")
h=$(jq -r '.height' <<<"$mon")
rr=$(jq -r '.refreshRate' <<<"$mon")
x=$(jq -r '.x' <<<"$mon")
y=$(jq -r '.y' <<<"$mon")

mode="${w}x${h}@${rr}"
pos="${x}x${y}"

hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$mode\", position = \"$pos\", scale = $scale })"
