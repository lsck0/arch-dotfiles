#!/usr/bin/env bash
# Toggle effect shader on/off.

set -e

DEFAULT="${HOME}/.config/hypr/shaders/color-correction.frag"
EFFECT="${HOME}/.config/hypr/shaders/crt-effect.frag"

current=$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')

if [[ "$current" == *crt-effect.frag ]]; then
    hyprctl keyword decoration:screen_shader "[[EMPTY]]"
    hyprctl keyword debug:damage_tracking 2
    hyprctl keyword decoration:screen_shader "$DEFAULT"
else
    hyprctl keyword decoration:screen_shader "[[EMPTY]]"
    hyprctl keyword debug:damage_tracking 0
    hyprctl keyword decoration:screen_shader "$EFFECT"
fi
