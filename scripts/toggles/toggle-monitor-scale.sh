#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Monitor scale and layout. `set` applies a scale live, then persists it to hyprland_monitors.lua;
# `live` and `layout` are runtime only, a reload restores the file. jq, not python: the display panel's chips run `live`.

MONITORS_LUA="$HOME/projects/arch-dotfiles/configs/desktop/hyprland/hyprland_monitors.lua"

# every output as json, disabled ones included
monitors_json() { hyprctl -j monitors all; }

# monitor_find <monitors json> <output>: that output's object, empty when absent
monitor_find() { jq -c --arg n "$2" '.[] | select(.name == $n)' <<<"$1"; }

default_monitor() { hyprctl -j monitors | jq -r '.[0].name // empty'; }

monitor_scale_get() { monitor_find "$(monitors_json)" "$1" | jq -r '.scale'; }

# monitor_lua_get <output> <key> <fallback>: a quoted field of the output's hl.monitor block
monitor_lua_get() {
    local value
    value=$(awk -v out="$1" -v key="$2" '
        $0 ~ "output *= *\"" out "\"" { inside = 1 }
        inside && $0 ~ "^ *" key " *= *\"" { sub(/^[^"]*"/, ""); sub(/".*/, ""); print; exit }
        inside && /^}\)/ { inside = 0 }
    ' "$MONITORS_LUA" 2>/dev/null || true)
    echo "${value:-$3}"
}

# monitor_lua_set_scale <output> <scale>: the value sits below the output key, so a block-aware awk rather than sed
monitor_lua_set_scale() {
    local updated
    updated=$(awk -v out="$1" -v scale="$2" '
        $0 ~ "output *= *\"" out "\"" { inside = 1 }
        inside && /^ *scale *=/ { sub(/scale *= *[0-9.]+/, "scale = " scale); found = 1 }
        /^}\)/ { inside = 0 }
        { print }
        END { exit !found }
    ' "$MONITORS_LUA") || { echo "no matching hl.monitor block for $1, not persisted" >&2; return 1; }
    printf '%s\n' "$updated" >"$MONITORS_LUA"
}

# monitor_scale_apply <output> <scale>: live, keeping mode and position
monitor_scale_apply() {
    local monitor out
    monitor=$(monitor_find "$(monitors_json)" "$1")
    [[ -n "$monitor" ]] || { echo "unknown monitor: $1" >&2; return 1; }
    out=$(hyprctl eval "$(jq -r --arg s "$2" '"hl.monitor({ output = \"\(.name)\", mode = \"\(.width)x\(.height)@\(.refreshRate)\", position = \"\(.x)x\(.y)\", scale = \($s) })"' <<<"$monitor")" 2>&1 || true)
    [[ "$out" == *ok* ]] || { echo "hyprctl rejected the scale: $out" >&2; return 1; }
}

monitor_scale_set() {
    local name=$1 scale=$2 applied
    monitor_scale_apply "$name" "$scale"
    # confirm the compositor took it before persisting: a fractional scale
    sleep 0.4
    applied=$(monitor_scale_get "$name")
    [[ -n "$applied" ]] || { echo "monitor disappeared after apply" >&2; return 1; }
    if ! awk -v a="$applied" -v b="$scale" 'BEGIN { exit !(a - b < 0.01 && b - a < 0.01) }'; then
        echo "hyprland adjusted the scale to $applied (asked for $scale); persisting the real value" >&2
        scale=$applied
    fi
    monitor_lua_set_scale "$name" "$scale"
    toggle_set monitor-scale "$name=$scale"
    toggle_notify -a Toggles "Monitor scale" "$name at ${scale}x"
}

# monitor_layout_set <output> extend|off|mirror [source]
monitor_layout_set() {
    local name=$1 action=$2 mirror_source=$3 monitors monitor scale others
    monitors=$(monitors_json)
    monitor=$(monitor_find "$monitors" "$name")
    [[ -n "$monitor" ]] || { echo "no such monitor: $name" >&2; return 1; }
    scale=$(jq -r '.scale' <<<"$monitor")
    awk -v s="$scale" 'BEGIN { exit !(s > 0) }' || scale=auto
    case "$action" in
    extend)
        # hl.monitor merges, so clear disabled and mirror explicitly
        hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$(monitor_lua_get "$name" mode highrr)\", position = \"$(monitor_lua_get "$name" position auto)\", scale = \"$scale\", disabled = false, mirror = \"\" })"
        ;;
    off)
        others=$(jq --arg n "$name" '[.[] | select(.name != $n and (.disabled | not) and .mirrorOf == "none")] | length' <<<"$monitors")
        ((others > 0)) || { echo "refusing to disable the last active monitor" >&2; return 1; }
        hyprctl eval "hl.monitor({ output = \"$name\", disabled = true })"
        ;;
    mirror)
        [[ -n "$mirror_source" && "$mirror_source" != "$name" ]] || { echo "mirror needs a source other than $name" >&2; return 1; }
        jq -e --arg s "$mirror_source" 'any(.[]; .name == $s and (.disabled | not) and .mirrorOf == "none")' <<<"$monitors" >/dev/null \
            || { echo "mirror source $mirror_source is not an active, unmirrored monitor" >&2; return 1; }
        hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$(monitor_lua_get "$name" mode highrr)\", position = \"auto\", scale = \"$scale\", disabled = false, mirror = \"$mirror_source\" })"
        ;;
    *) usage; return 1 ;;
    esac
}

usage() {
    echo "usage: $(basename "$0") {get [monitor]|label|list|set <scale> [monitor]|live <scale> [monitor]|layout <monitor> extend|off|mirror <source>}" >&2
}

case "${1:-label}" in
get) monitor_scale_get "${2:-$(default_monitor)}" ;;
label)
    m=$(default_monitor)
    echo "󰍹 Scale: $m $(monitor_scale_get "$m")x"
    ;;
list) hyprctl -j monitors | jq -r '.[] | "\(.name)\t\(.width)x\(.height)@\(.refreshRate)\t\(.scale)"' ;;
set | live)
    [[ $# -ge 2 ]] || { usage; exit 1; }
    [[ $2 =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "scale must be a number" >&2; exit 1; }
    if [[ $1 == set ]]; then monitor_scale_set "${3:-$(default_monitor)}" "$2"; else monitor_scale_apply "${3:-$(default_monitor)}" "$2"; fi
    ;;
layout)
    [[ $# -ge 3 ]] || { usage; exit 1; }
    monitor_layout_set "$2" "$3" "${4:-}"
    ;;
*) usage; exit 1 ;;
esac
