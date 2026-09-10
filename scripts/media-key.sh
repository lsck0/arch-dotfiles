#!/usr/bin/env bash
# Volume / microphone / brightness keys, routed through the shell.
#
# WHY THIS EXISTS. The media keys used to call `pactl` and `brightnessctl`
# directly from hyprland_keybindings.lua. Two problems with that:
#
#   1. **A live bug.** The volume binds were `pactl set-sink-volume 0 …` — a
#      HARDCODED SINK INDEX, not the default sink. On this machine the only
#      sink is index 58, so `0` was already wrong; it happened to resolve
#      because there is exactly one sink. Plug in Bluetooth headphones or an
#      HDMI display and the volume keys start adjusting whichever device
#      pactl picks, not the one you are listening to. `@DEFAULT_SINK@` is
#      both correct and self-documenting.
#
#   2. The shell had to *infer* the change second-hand. The OSD is now driven
#      by the same action that makes the change, so it can never disagree
#      with reality or lag behind it.
#
# DUAL-BINDING PRINCIPLE (from end-4's shells): the raw action always runs
# first and never depends on the shell. If quickshell is dead the volume
# still changes — you just do not get the OSD. A broken shell must not cost
# you your volume keys.

# omarchy:summary=Adjust volume/mic/brightness and show the OSD
# omarchy:args=volume-up|volume-down|volume-mute|mic-mute|brightness-up|brightness-down
# omarchy:examples=media-key.sh volume-up | media-key.sh brightness-down

set -uo pipefail

STEP_VOL=5
STEP_BRI=5
QS_CONFIG="$HOME/.config/quickshell"

# Speaks the OSD's OWN vocabulary rather than passing raw glyphs:
# OsdModel.js's iconFor() maps semantic names ("volume", "volume-muted",
# "brightness", "microphone-muted", …) to glyphs itself, so the icon set
# stays owned in one place instead of being duplicated here.
#
# The progress-bar contract is easy to get wrong: OsdModel gives you a bar
# only when a value is present AND the message is EMPTY (it then renders the
# percentage as the message itself). Passing both a message and a value
# silently yields a text-only OSD with no bar — which is exactly what the
# first version of this script did.
osd_value() { # semantic-icon, value  -> progress bar
    timeout 2 quickshell ipc -p "$QS_CONFIG" call osd present \
        "$(jq -cn --arg i "$1" --argjson v "$2" '{icon:$i, value:$v}')" >/dev/null 2>&1 || true
}
osd_text() {  # semantic-icon, message -> text only
    timeout 2 quickshell ipc -p "$QS_CONFIG" call osd present \
        "$(jq -cn --arg i "$1" --arg m "$2" '{icon:$i, message:$m}')" >/dev/null 2>&1 || true
}

sink_volume() { # integer percent of the DEFAULT sink
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

case "${1:-}" in
volume-up|volume-down)
    if [[ $1 == volume-up ]]; then
        pactl set-sink-volume @DEFAULT_SINK@ "+${STEP_VOL}%" >/dev/null 2>&1
        # pactl will happily go past 100% and clip.
        v=$(sink_volume); [[ -n "${v:-}" && "$v" -gt 100 ]] && pactl set-sink-volume @DEFAULT_SINK@ 100% >/dev/null 2>&1
        # Raising the volume unmutes: pressing volume-up on a muted sink and
        # having nothing audible happen is the wrong behaviour.
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
        # `5%-` can reach 0 and leave a black screen with no obvious way back.
        b=$(brightness_pct); [[ -n "${b:-}" && "$b" -lt 1 ]] && brightnessctl -q set 1% >/dev/null 2>&1
    fi
    b=$(brightness_pct); osd_value "brightness" "${b:-0}"
    ;;
*)
    echo "usage: $(basename "$0") {volume-up|volume-down|volume-mute|mic-mute|brightness-up|brightness-down}" >&2
    exit 1
    ;;
esac
