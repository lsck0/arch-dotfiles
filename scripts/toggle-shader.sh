#!/usr/bin/env bash
# Toggle effect shader on/off.

set -e

DEFAULT="${HOME}/.config/hypr/shaders/color-correction.frag"
EFFECT="${HOME}/.config/hypr/shaders/crt-effect.frag"

# `hyprctl keyword` refuses to run against a Lua config ("keyword can't work
# with non-legacy parsers"), so set the values by evaluating Lua instead.
# Clearing the shader first is what makes Hyprland pick up the new one.
set_shader() {
    local damage="$1" shader="$2"

    hyprctl eval 'hl.config({ decoration = { screen_shader = "" } })' >/dev/null
    hyprctl eval "hl.config({ debug = { damage_tracking = ${damage} } })" >/dev/null
    hyprctl eval "hl.config({ decoration = { screen_shader = [[${shader}]] } })" >/dev/null
}

current=$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')

if [[ "$current" == *crt-effect.frag ]]; then
    set_shader 2 "$DEFAULT"
else
    set_shader 0 "$EFFECT"
fi
