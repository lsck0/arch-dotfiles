#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# focus mode: a scene, not a new capability

PARTS=(dnd keep-awake nightlight)
SCRIPTS=(toggle-dnd.sh toggle-keep-awake.sh toggle-nightlight.sh)
SAVE="$TOGGLES_RUNTIME_DIR/focus-previous"
# the grading preset is n-state: recorded by name next to the on/off parts, put back with `set`
FOCUS_PRESET=grayscale

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
    printf 'color-grading %s\n' "$(./toggle-color-grading.sh get 2>/dev/null || echo default)" >>"$SAVE"
    ./toggle-color-grading.sh set "$FOCUS_PRESET" >/dev/null 2>&1 || true
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
    local preset=""
    [[ -s "$SAVE" ]] && preset=$(awk '$1 == "color-grading" { print $2 }' "$SAVE")
    # no record: the default grade
    if [[ -n "$preset" ]]; then
        ./toggle-color-grading.sh set "$preset" >/dev/null 2>&1 || true
    else
        ./toggle-color-grading.sh on >/dev/null 2>&1 || true
    fi
    rm -f "$SAVE"
    toggle_set_volatile focus off
}

toggle_main focus "Focus Mode" check turn_on turn_off "${1:-toggle}"
