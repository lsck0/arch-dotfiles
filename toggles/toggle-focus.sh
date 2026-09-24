#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# "Focus mode" — a scene, not a new capability.

PARTS=(dnd keep-awake nightlight)
SCRIPTS=(toggle-dnd.sh toggle-keep-awake.sh toggle-nightlight.sh)
SAVE="$TOGGLES_RUNTIME_DIR/focus-previous"

check() { toggle_get_volatile focus; }

turn_on() {
    # Record what each part was BEFORE we touch it, so `off` can put it back.
    : >"$SAVE"
    local i state
    for i in "${!PARTS[@]}"; do
        state=$("./${SCRIPTS[$i]}" get 2>/dev/null || echo off)
        printf '%s %s\n' "${PARTS[$i]}" "$state" >>"$SAVE"
        [[ "$state" == on ]] || "./${SCRIPTS[$i]}" on >/dev/null 2>&1 || true
    done
    toggle_set_volatile focus on
}

turn_off() {
    local i name want
    for i in "${!PARTS[@]}"; do
        want=off
        [[ -s "$SAVE" ]] && want=$(awk -v n="${PARTS[$i]}" '$1 == n { print $2 }' "$SAVE")
        # No record (focus was on before a reboot, or the file was lost): default to off, which is the safe direction — it cannot leave the machine silently muted.
        [[ "${want:-off}" == on ]] || "./${SCRIPTS[$i]}" off >/dev/null 2>&1 || true
    done
    rm -f "$SAVE"
    toggle_set_volatile focus off
}

toggle_main focus "Focus Mode" check turn_on turn_off "${1:-toggle}"
