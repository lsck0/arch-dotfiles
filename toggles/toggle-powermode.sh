#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# 3-state power profile switch, matching TLP's own native forced modes
# (`tlp performance|balanced|power-saver`) rather than power-profiles-daemon
# (not installed, would conflict with TLP anyway). Not a toggle_main-style
# on/off toggle — cycles through the 3 states in order. TLP has no clean
# query for "currently forced state", so we track it ourselves in tmpfs, not
# the persistent store: tlp.service always resets to auto-detect on boot, so
# a persistent flag would lie about the state a reboot already cleared.
#
# Default policy (2026-09-06): the actual boot-time default lives in
# configs/tlp/tlp.conf (battery-equipped hardware: balanced on AC,
# power-saver on battery) vs. configs/tlp/tlp.conf.ac-only (no-battery
# hardware: performance always) — configs/tlp/link.sh picks whichever file
# applies at install time. This script only ever overrides that default at
# runtime ("manual mode" in TLP's own terms); every override is undone by
# `auto` below, or implicitly by the next reboot, since tlp.service always
# starts in auto-detect mode.
STATES=(balanced performance power-saver)
ICONS=(⚖ ⚡ 🔋)
LABELS=("Balanced" "Performance" "Power Saver")

current() { toggle_get_volatile powermode; }

index_of() {
    local s
    for i in "${!STATES[@]}"; do
        s=${STATES[$i]}
        [[ "$s" == "$1" ]] && { echo "$i"; return; }
    done
    echo -1 # unset/unrecognized -> no forced override (auto-detect)
}

apply() {
    local state=$1
    sudo tlp "$state"
    toggle_set_volatile powermode "$state"
    toggle_set powermode "$state"
    toggle_notify -a Toggles "Power Mode" "${LABELS[$(index_of "$state")]}"
}

# Clears any forced override and returns TLP to its own AC/BAT auto-detect
# (i.e. the real configured default — balanced/power-saver on battery
# hardware, performance on AC-only hardware). Distinct from `apply`: this
# does not force one static profile, it un-forces whatever was forced.
reset_auto() {
    sudo tlp start >/dev/null
    rm -f "$TOGGLES_RUNTIME_DIR/powermode" 2>/dev/null || true
    toggle_set powermode ""
    toggle_notify -a Toggles "Power Mode" "Auto (default)"
}

action=${1:-toggle}
state=$(current)
idx=$(index_of "$state")

case "$action" in
get)
    # Empty means "no override" -- the caller should read that as auto /
    # hardware default, not silently coerce it to a state name.
    [[ $idx -ge 0 ]] && echo "${STATES[$idx]}" || echo ""
    ;;
label)
    if [[ $idx -ge 0 ]]; then
        echo "${ICONS[$idx]} Power: ${LABELS[$idx]}"
    else
        echo "⚙ Power: Auto (default)"
    fi
    ;;
toggle)
    next=$(((idx + 1) % ${#STATES[@]}))
    apply "${STATES[$next]}"
    ;;
performance | balanced | power-saver)
    apply "$action"
    ;;
auto)
    reset_auto
    ;;
*)
    echo "usage: $(basename "$0") {get|label|toggle|performance|balanced|power-saver|auto}" >&2
    exit 1
    ;;
esac
