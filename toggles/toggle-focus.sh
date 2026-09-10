#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# "Focus mode" — a scene, not a new capability. Composes toggles that already
# exist rather than reimplementing any of them, so each part stays
# independently controllable and this file has no logic of its own to rot.
#
# What it does:
#   DND on          — silence notifications (they still land in history)
#   keep-awake on   — no dimming or sleeping mid-thought
#   night light on  — warmer screen for a long session
#
# What it deliberately does NOT do:
#   * touch the network. Offline mode is a much bigger hammer and most focus
#     work still needs the internet; conflating the two would make this
#     unusable for the common case.
#   * change power mode. A focus session on battery and one on AC want
#     opposite things, and this cannot tell which you meant.
#
# RESTORES WHAT IT FOUND, rather than blindly turning everything off on the
# way out. Turning focus mode off should not silence a night light you had
# on beforehand for your own reasons — that is the difference between a
# scene and a sledgehammer.

PARTS=(dnd keep-awake nightlight)
SCRIPTS=(toggle-dnd.sh toggle-keep-awake.sh toggle-nightlight.sh)
SAVE="$TOGGLES_RUNTIME_DIR/focus-previous"

check() { toggle_get_volatile focus; }

turn_on() {
    # Record what each part was BEFORE we touch it, so `off` can put it back.
    # Volatile: a reboot mid-focus should not leave a stale restore list
    # claiming things were on.
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
        # No record (focus was on before a reboot, or the file was lost):
        # default to off, which is the safe direction — it cannot leave the
        # machine silently muted.
        [[ "${want:-off}" == on ]] || "./${SCRIPTS[$i]}" off >/dev/null 2>&1 || true
    done
    rm -f "$SAVE"
    toggle_set_volatile focus off
}

toggle_main focus "Focus Mode" check turn_on turn_off "${1:-toggle}"
