#!/usr/bin/env bash

set -uo pipefail

STEP_VOL=5
STEP_BRI=5
QS_CONFIG="$HOME/.config/quickshell"

# semantic icon names, OsdModel.js maps them to glyphs
osd_value() {
    timeout 2 quickshell ipc -p "$QS_CONFIG" call osd present \
        "$(jq -cn --arg i "$1" --argjson v "$2" '{icon:$i, value:$v}')" >/dev/null 2>&1 || true
}
osd_text() {
    timeout 2 quickshell ipc -p "$QS_CONFIG" call osd present \
        "$(jq -cn --arg i "$1" --arg m "$2" '{icon:$i, message:$m}')" >/dev/null 2>&1 || true
}

sink_volume() {
    pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '\d+(?=%)' | head -1
}
sink_muted() { [[ "$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null)" == *yes* ]]; }
source_muted() { [[ "$(pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null)" == *yes* ]]; }

brightness_pct() {
    local cur max
    cur=$(brightnessctl -m get 2>/dev/null) || return 1
    max=$(brightnessctl -m max 2>/dev/null) || return 1
    ((max > 0)) && echo $(( cur * 100 / max )) || echo 0
}

# kbd backlight is often a 3-step switch (max 2), not a percentage
kbd_device() {
    local d
    for d in /sys/class/leds/*kbd_backlight*; do
        [[ -e "$d/brightness" ]] && { basename "$d"; return 0; }
    done
    return 1
}

kbd_set() {
    brightnessctl -q -d "$1" set "$2" >/dev/null 2>&1
}

kbd_osd() {
    local cur=$1 max=$2 pct
    ((max > 0)) || return
    pct=$(( cur * 100 / max ))
    if ((cur == 0)); then
        osd_text "keyboard-backlight-off" "Keyboard light off"
    else
        osd_value "keyboard-backlight" "$pct"
    fi
}

case "${1:-}" in
volume-up|volume-down)
    if [[ $1 == volume-up ]]; then
        pactl set-sink-volume @DEFAULT_SINK@ "+${STEP_VOL}%" >/dev/null 2>&1
        # pactl can exceed 100%
        v=$(sink_volume); [[ -n "${v:-}" && "$v" -gt 100 ]] && pactl set-sink-volume @DEFAULT_SINK@ 100% >/dev/null 2>&1
        # raising the volume unmutes
        pactl set-sink-mute @DEFAULT_SINK@ 0 >/dev/null 2>&1
    else
        pactl set-sink-volume @DEFAULT_SINK@ "-${STEP_VOL}%" >/dev/null 2>&1
    fi
    v=$(sink_volume); v=${v:-0}
    if sink_muted; then osd_text "volume-muted" "Muted"; else osd_value "volume" "$v"; fi
    ;;
volume-mute)
    pactl set-sink-mute @DEFAULT_SINK@ toggle >/dev/null 2>&1
    if sink_muted; then
        osd_text "volume-muted" "Muted"
    else
        v=$(sink_volume); osd_value "volume" "${v:-0}"
    fi
    ;;
mic-mute)
    pactl set-source-mute @DEFAULT_SOURCE@ toggle >/dev/null 2>&1
    if source_muted; then osd_text "microphone-muted" "Mic muted"
    else osd_text "microphone" "Mic live"; fi
    ;;
brightness-up|brightness-down)
    if [[ $1 == brightness-up ]]; then
        brightnessctl -q set "${STEP_BRI}%+" >/dev/null 2>&1
    else
        brightnessctl -q set "${STEP_BRI}%-" >/dev/null 2>&1
        # never reach a black screen
        b=$(brightness_pct); [[ -n "${b:-}" && "$b" -lt 1 ]] && brightnessctl -q set 1% >/dev/null 2>&1
    fi
    b=$(brightness_pct); osd_value "brightness" "${b:-0}"
    ;;
kbd-backlight-up|kbd-backlight-down|kbd-backlight-toggle)
    dev=$(kbd_device) || { osd_text "keyboard-backlight-off" "No keyboard backlight"; exit 0; }
    cur=$(brightnessctl -d "$dev" -m get 2>/dev/null) || exit 0
    max=$(brightnessctl -d "$dev" -m max 2>/dev/null) || exit 0
    case "$1" in
    kbd-backlight-up)     next=$(( cur + 1 )); ((next > max)) && next=$max ;;
    kbd-backlight-down)   next=$(( cur - 1 )); ((next < 0)) && next=0 ;;
    # cycle so the dim step is reachable
    kbd-backlight-toggle) next=$(( (cur + 1) % (max + 1) )) ;;
    esac
    kbd_set "$dev" "$next"
    kbd_osd "$next" "$max"
    ;;
*)
    echo "usage: $(basename "$0") {volume-up|volume-down|volume-mute|mic-mute|brightness-up|brightness-down|kbd-backlight-up|kbd-backlight-down|kbd-backlight-toggle}" >&2
    exit 1
    ;;
esac
