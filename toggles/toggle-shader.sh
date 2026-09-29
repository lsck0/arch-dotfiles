#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Hyprland's single screen_shader slot: off, nightlight, color-grading, cyberpunk.

SHADER_DIR="${HOME}/.config/hypr/shaders"
STATES=(off nightlight color-grading cyberpunk)
LABELS=("Off" "Night light" "Color grading" "Cyberpunk")
CYBERPUNK_TEMPLATE="${SHADER_DIR}/crt-effect.frag"
CYBERPUNK_SHADER="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/crt-effect.frag"

index_of() {
    local i
    for i in "${!STATES[@]}"; do
        [[ "${STATES[$i]}" == "$1" ]] && { echo "$i"; return; }
    done
    echo -1
}

current() {
    case "$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')" in
    "") echo off ;;
    */nightlight.frag) echo nightlight ;;
    */color-correction.frag) echo color-grading ;;
    */crt-effect.frag) echo cyberpunk ;;
    *) echo custom ;;
    esac
}

# theme constants from the shell palette, template defaults otherwise
render_cyberpunk() {
    local palette script
    palette=$(timeout 3 qs ipc -p "${HOME}/.config/quickshell" call shell palette 2>/dev/null) || palette=""
    if ! script=$(jq -er '
        def float: tostring | if test("[.e]") then . else . + ".0" end;
        def vec3: "vec3(\(.[0] | float), \(.[1] | float), \(.[2] | float))";
        if [.background[], .accent[], .glowStrength, .scanlineOpacity, .scanlineSpacing] | all(type == "number")
        then . else error("bad palette") end |
        "s|^const vec3 BACKGROUND = .*|const vec3 BACKGROUND = \(.background | vec3);|",
        "s|^const vec3 ACCENT = .*|const vec3 ACCENT = \(.accent | vec3);|",
        "s|^const float GLOW = .*|const float GLOW = \(.glowStrength | float);|",
        "s|^const float SCANLINE_OPACITY = .*|const float SCANLINE_OPACITY = \(.scanlineOpacity | float);|",
        "s|^const float SCANLINE_SPACING_PX = .*|const float SCANLINE_SPACING_PX = \(.scanlineSpacing | float);|"
    ' <<<"$palette" 2>/dev/null); then
        cp "$CYBERPUNK_TEMPLATE" "$CYBERPUNK_SHADER"
        return
    fi
    sed "$script" "$CYBERPUNK_TEMPLATE" >"$CYBERPUNK_SHADER.tmp" && mv "$CYBERPUNK_SHADER.tmp" "$CYBERPUNK_SHADER"
}

# hyprctl keyword rejects Lua configs; damage_tracking 0 for animated shaders
load() {
    local damage=$1 shader=$2
    hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })' >/dev/null
    hyprctl eval "hl.config({ debug = { damage_tracking = ${damage} } })" >/dev/null
    hyprctl eval "hl.config({ decoration = { screen_shader = [[${shader}]] } })" >/dev/null
}

apply() {
    local state=$1
    case "$state" in
    off) load 2 "" ;;
    nightlight) load 2 "${SHADER_DIR}/nightlight.frag" ;;
    color-grading) load 2 "${SHADER_DIR}/color-correction.frag" ;;
    cyberpunk)
        render_cyberpunk
        load 0 "$CYBERPUNK_SHADER"
        ;;
    esac
    toggle_set shader "$state"
    toggle_notify -a Toggles "Shader" "${LABELS[$(index_of "$state")]}"
}

action=${1:-toggle}
state=$(current)
idx=$(index_of "$state")

case "$action" in
get)
    echo "$state"
    ;;
label)
    if [[ "$state" == off ]]; then
        echo "○ Shader: Off"
    elif [[ $idx -ge 0 ]]; then
        echo "● Shader: ${LABELS[$idx]}"
    else
        echo "● Shader: Custom"
    fi
    ;;
toggle)
    apply "${STATES[$(((idx + 1) % ${#STATES[@]}))]}"
    ;;
off | nightlight | color-grading | cyberpunk)
    apply "$action"
    ;;
*)
    echo "usage: $(basename "$0") {get|label|toggle|off|nightlight|color-grading|cyberpunk}" >&2
    exit 1
    ;;
esac
