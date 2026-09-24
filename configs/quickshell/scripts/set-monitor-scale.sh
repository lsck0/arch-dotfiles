#!/usr/bin/env bash
# Applies a monitor scale change at runtime, keeping the connector's current mode and position untouched.
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
