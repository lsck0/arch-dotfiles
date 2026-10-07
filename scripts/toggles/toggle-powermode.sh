#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
source ./lib.sh
source ../lib/platform.sh

# 3-state switch via tlp's native forced modes (not power-profiles-daemon, which would conflict)
STATES=(balanced performance power-saver)
ICONS=(⚖ ⚡ 🔋)
LABELS=("Balanced" "Performance" "Power Saver")

current() { toggle_get_volatile powermode; }

# a laptop off its battery per upower; a desktop on a ups never counts
on_battery() {
    [[ "$(platform_form_factor ..)" == laptop ]] || return 1
    [[ "$(busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery 2>/dev/null)" == "b true" ]]
}

# the one saver rule: forced power-saver, or auto on a laptop's battery; a forced balanced or performance wins
saver_get() {
    local state
    state=$(current)
    if [[ "$state" == power-saver ]] || { [[ $(toggle_index_of "$state" -1 "${STATES[@]}") -lt 0 ]] && on_battery; }; then
        echo on
    else
        echo off
    fi
}

# hyprland and quickshell read the volatile powersaver state themselves
refresh_desktop() {
    local ghostty_conf="$TOGGLES_RUNTIME_DIR/ghostty-powersave.conf"
    if [[ "$(toggle_get_volatile powersaver)" == on ]]; then
        echo "cursor-style-blink = false" >"$ghostty_conf"
    else
        rm -f "$ghostty_conf"
    fi
    # ghostty has no config watcher, reload-config is only reachable over d-bus
    timeout 3 gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty \
        --method org.gtk.Actions.Activate reload-config '[]' '{}' >/dev/null 2>&1 || true
    hyprctl reload config-only >/dev/null 2>&1 || true
    # the reload drops the runtime-only shader and monitor layout
    ./toggle-shader.sh reapply >/dev/null 2>&1 || true
    ./toggle-monitor-scale.sh reapply >/dev/null 2>&1 || true
    timeout 3 qs ipc -p "$HOME/.config/quickshell" call shell reloadPowerMode >/dev/null 2>&1 || true
}

# after a mode or power source change; the desktop reloads only when saver flips
sync_saver() {
    local saver
    saver=$(saver_get)
    [[ "$(toggle_get_volatile powersaver)" == "$saver" ]] && return
    toggle_set_volatile powersaver "$saver"
    refresh_desktop
}

apply() {
    local state=$1
    sudo tlp "$state"
    toggle_set_volatile powermode "$state"
    sync_saver
    toggle_notify -a Toggles "Power Mode" "${LABELS[$(toggle_index_of "$state" -1 "${STATES[@]}")]}"
}

# un-force: return tlp to its own ac/bat auto-detect, not a static profile
reset_auto() {
    sudo tlp start >/dev/null
    rm -f "$TOGGLES_RUNTIME_DIR/powermode" 2>/dev/null || true
    sync_saver
    toggle_notify -a Toggles "Power Mode" "Auto (default)"
}

action=${1:-toggle}
state=$(current)
# -1 is no forced mode: tlp auto-detects
idx=$(toggle_index_of "$state" -1 "${STATES[@]}")

case "$action" in
get)
    # empty means no override: auto / hardware default
    [[ $idx -ge 0 ]] && echo "${STATES[$idx]}" || echo ""
    ;;
label)
    # a forced mode counts as on, auto is the default
    if [[ $idx -ge 0 ]]; then
        echo "● ${ICONS[$idx]} Power: ${LABELS[$idx]}"
    else
        echo "○ ⚙ Power: Auto (default)"
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
sync)
    sync_saver
    ;;
*)
    echo "usage: $(basename "$0") {get|label|toggle|performance|balanced|power-saver|auto|sync}" >&2
    exit 1
    ;;
esac
