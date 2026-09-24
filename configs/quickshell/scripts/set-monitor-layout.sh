#!/usr/bin/env bash
# Extends, mirrors or disables one output at runtime through `hyprctl eval`
# (`hyprctl keyword` refuses Lua configs, see set-monitor-scale.sh).
# Runtime only: a reload or relogin restores hyprland_monitors.lua.
set -uo pipefail

usage="usage: set-monitor-layout.sh <output> extend|off|mirror <source-output>"
name="${1:?$usage}"
action="${2:?$usage}"

monitors=$(hyprctl -j monitors all) || exit 1
mon=$(jq -c --arg n "$name" '.[] | select(.name == $n)' <<<"$monitors")
[[ -n "$mon" ]] || { echo "no such monitor: $name" >&2; exit 1; }

scale=$(jq -r '.scale' <<<"$mon")
awk -v s="$scale" 'BEGIN { exit !(s > 0) }' || scale=auto

monitors_lua="$(dirname "$(readlink -f "$0")")/../../hyprland/hyprland_monitors.lua"

# configured <field> <fallback>: the field from this output's hl.monitor block.
configured() {
    local v
    v=$(awk -v out="$name" -v key="$1" '
        $0 ~ "output *= *\"" out "\"" { inside = 1 }
        inside && $0 ~ "^ *" key " *= *\"" { sub(/^[^"]*"/, ""); sub(/".*/, ""); print; exit }
        inside && /^}\)/ { inside = 0 }
    ' "$monitors_lua" 2>/dev/null)
    echo "${v:-$2}"
}

case "$action" in
    extend)
        # hl.monitor merges into the existing rule, so disabled/mirror must be cleared explicitly.
        hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$(configured mode highrr)\", position = \"$(configured position auto)\", scale = \"$scale\", disabled = false, mirror = \"\" })"
        ;;
    off)
        # Never leave the session without a screen to turn it back on from.
        others=$(jq --arg n "$name" '[.[] | select(.name != $n and (.disabled | not) and .mirrorOf == "none")] | length' <<<"$monitors")
        (( others > 0 )) || { echo "refusing to disable the last active monitor" >&2; exit 1; }
        hyprctl eval "hl.monitor({ output = \"$name\", disabled = true })"
        ;;
    mirror)
        source="${3:?$usage}"
        [[ "$source" != "$name" ]] || { echo "a monitor cannot mirror itself" >&2; exit 1; }
        src=$(jq -c --arg s "$source" '.[] | select(.name == $s and (.disabled | not) and .mirrorOf == "none")' <<<"$monitors")
        [[ -n "$src" ]] || { echo "mirror source $source is not an active, unmirrored monitor" >&2; exit 1; }
        hyprctl eval "hl.monitor({ output = \"$name\", mode = \"$(configured mode highrr)\", position = \"auto\", scale = \"$scale\", disabled = false, mirror = \"$source\" })"
        ;;
    *)
        echo "$usage" >&2
        exit 1
        ;;
esac
