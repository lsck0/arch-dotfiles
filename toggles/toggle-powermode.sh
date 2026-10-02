#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh

# 3-state switch via tlp's native forced modes (not power-profiles-daemon, which would conflict)
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
    echo -1 # unset/unrecognized: no forced override (auto-detect)
}

# hyprland and quickshell read the volatile state themselves, only power-saver changes them
refresh_desktop() {
    local ghostty_conf="$TOGGLES_RUNTIME_DIR/ghostty-powersave.conf"
    if [[ "$(current)" == power-saver ]]; then
        echo "cursor-style-blink = false" >"$ghostty_conf"
    else
        rm -f "$ghostty_conf"
    fi
    # ghostty has no config watcher, reload-config is only reachable over d-bus
    timeout 3 gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty \
        --method org.gtk.Actions.Activate reload-config '[]' '{}' >/dev/null 2>&1 || true
    hyprctl reload config-only >/dev/null 2>&1 || true
    timeout 3 qs ipc -p "$HOME/.config/quickshell" call shell reloadPowerMode >/dev/null 2>&1 || true
}

apply() {
    local state=$1 was
    was=$(current)
    sudo tlp "$state"
    toggle_set_volatile powermode "$state"
    toggle_set powermode "$state"
    if [[ "$was" == power-saver || "$state" == power-saver ]]; then
        refresh_desktop
    fi
    toggle_notify -a Toggles "Power Mode" "${LABELS[$(index_of "$state")]}"
}

# un-force: return tlp to its own ac/bat auto-detect, not a static profile
reset_auto() {
    local was
    was=$(current)
    sudo tlp start >/dev/null
    rm -f "$TOGGLES_RUNTIME_DIR/powermode" 2>/dev/null || true
    toggle_set powermode ""
    if [[ "$was" == power-saver ]]; then
        refresh_desktop
    fi
    toggle_notify -a Toggles "Power Mode" "Auto (default)"
}

action=${1:-toggle}
state=$(current)
idx=$(index_of "$state")

case "$action" in
get)
    # empty means no override: auto / hardware default
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
