#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# n-state preset cycler; the preset table and its state live in color-grading.py, never here
GRADING=../../configs/desktop/color-grading/color-grading.py

mapfile -t PRESETS < <("$GRADING" list)
current=$("$GRADING" get preset)

label_of() { "$GRADING" status | jq -r --arg n "$1" '.presets[] | select(.name == $n) | .label'; }

apply() {
    "$GRADING" set preset "$1"
    toggle_notify -a Toggles "Color grading" "$(label_of "$1")"
}

case "${1:-toggle}" in
get)
    echo "$current"
    ;;
list)
    printf '%s\n' "${PRESETS[@]}"
    ;;
label)
    if [[ "$current" == off ]]; then echo "○ Color grading: Off"; else echo "● Color grading: $(label_of "$current")"; fi
    ;;
on)
    apply default
    ;;
off)
    apply off
    ;;
toggle)
    for i in "${!PRESETS[@]}"; do
        [[ "${PRESETS[$i]}" == "$current" ]] && { apply "${PRESETS[$(((i + 1) % ${#PRESETS[@]}))]}"; exit 0; }
    done
    apply default
    ;;
set)
    # color-grading.py parses the name and rejects unknown presets
    apply "${2:?usage: $(basename "$0") set <preset>}"
    ;;
*)
    echo "usage: $(basename "$0") {get|list|label|on|off|toggle|set <preset>}" >&2
    exit 1
    ;;
esac
