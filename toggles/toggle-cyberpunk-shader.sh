#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# Same shader pair and hyprctl approach as scripts/toggle-shader.sh (bound to
# SUPER+SHIFT+C directly for a quick keypress); this wraps the same effect
# with on/off semantics so it also shows up in the toggles menu/waybar.
DEFAULT_SHADER="${HOME}/.config/hypr/shaders/color-correction.frag"
CYBERPUNK_SHADER="${HOME}/.config/hypr/shaders/crt-effect.frag"

# `hyprctl keyword` refuses to run against a Lua config ("keyword can't work
# with non-legacy parsers"), so set the values by evaluating Lua instead.
# Clearing the shader first is what makes Hyprland pick up the new one.
set_shader() {
    local damage=$1 shader=$2
    hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })' >/dev/null
    hyprctl eval "hl.config({ debug = { damage_tracking = ${damage} } })" >/dev/null
    hyprctl eval "hl.config({ decoration = { screen_shader = [[${shader}]] } })" >/dev/null
}

check() {
    local current
    current=$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')
    [[ "$current" == *crt-effect.frag ]] && echo on || echo off
}
turn_on() { set_shader 0 "$CYBERPUNK_SHADER"; }
turn_off() { set_shader 2 "$DEFAULT_SHADER"; }

toggle_main cyberpunk-shader "Cyberpunk Shader" check turn_on turn_off "${1:-toggle}"
