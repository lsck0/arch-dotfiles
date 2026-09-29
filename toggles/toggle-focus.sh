#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# focus mode: a scene, not a new capability

PARTS=(dnd keep-awake)
SCRIPTS=(toggle-dnd.sh toggle-keep-awake.sh)
SAVE="$TOGGLES_RUNTIME_DIR/focus-previous"
# the shader slot is n-state, so it is saved by name and put back with `set`, not on/off
SHADER_SAVE="$TOGGLES_RUNTIME_DIR/focus-previous-shader"

check() { toggle_get_volatile focus; }

turn_on() {
    # a second `on` would record the focus scene itself as the state to restore
    [[ "$(check)" == on ]] && return 0
    # Record what each part was BEFORE we touch it, so `off` can put it back.
    : >"$SAVE"
    local i state
    for i in "${!PARTS[@]}"; do
        state=$("./${SCRIPTS[$i]}" get 2>/dev/null || echo off)
        printf '%s %s\n' "${PARTS[$i]}" "$state" >>"$SAVE"
        [[ "$state" == on ]] || "./${SCRIPTS[$i]}" on >/dev/null 2>&1 || true
    done
    ./toggle-shader.sh get >"$SHADER_SAVE" 2>/dev/null || true
    ./toggle-shader.sh nightlight >/dev/null 2>&1 || true
    toggle_set_volatile focus on
}

turn_off() {
    local i name want
    for i in "${!PARTS[@]}"; do
        want=off
        [[ -s "$SAVE" ]] && want=$(awk -v n="${PARTS[$i]}" '$1 == n { print $2 }' "$SAVE")
        # no record: default to off, the safe direction (never leaves the machine silently muted)
        [[ "${want:-off}" == on ]] || "./${SCRIPTS[$i]}" off >/dev/null 2>&1 || true
    done
    rm -f "$SAVE"
    # no record: back to the startup grade from hyprland_windows.lua
    local shader
    shader=$(cat "$SHADER_SAVE" 2>/dev/null || true)
    case "$shader" in
    off | nightlight | color-grading | cyberpunk) ;;
    *) shader=color-grading ;;
    esac
    ./toggle-shader.sh "$shader" >/dev/null 2>&1 || true
    rm -f "$SHADER_SAVE"
    toggle_set_volatile focus off
}

toggle_main focus "Focus Mode" check turn_on turn_off "${1:-toggle}"
