#!/bin/bash
# Audible + visual alert that must be dismissed by hand.
#
# For things you asked to be interrupted by — a reminder elapsing, a pomodoro
# phase ending. An ordinary notification toast is the wrong shape for those:
# it auto-expires, so one that fires while you are looking elsewhere is
# simply gone. This pairs a sound with the large top-left card in
# configs/quickshell/plugins/alert/, which stays up until clicked.
#
# Ordinary confirmations ("reminder set", "pomodoro stopped") deliberately do
# NOT come through here — they still use notification-send. Blocking on those
# would train you to dismiss alerts without reading them.
#
# The sound is played here rather than in QML on purpose: a reminder should
# still be audible when quickshell is down, and this script falls back to a
# plain notification in that case so the alert is never silently lost.

# omarchy:summary=Audible, manually-dismissed alert card
# omarchy:args=<title> [body] [glyph]
# omarchy:examples=alert.sh "Reminder" "Check the oven" | alert.sh "Focus done" "Take a break"

set -uo pipefail

TITLE=${1:-Reminder}
BODY=${2:-}
GLYPH=${3:-󰀠}   # md-alarm

SOUND=/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga

play_sound() {
    # Backgrounded and fully detached: an alert must never block on audio,
    # and a systemd transient unit that exits while paplay is still writing
    # would otherwise cut the sound off.
    if command -v canberra-gtk-play >/dev/null 2>&1; then
        setsid canberra-gtk-play -i alarm-clock-elapsed >/dev/null 2>&1 &
    elif [[ -r "$SOUND" ]] && command -v paplay >/dev/null 2>&1; then
        setsid paplay "$SOUND" >/dev/null 2>&1 &
    elif [[ -r "$SOUND" ]] && command -v pw-play >/dev/null 2>&1; then
        setsid pw-play "$SOUND" >/dev/null 2>&1 &
    fi
    return 0
}

show_card() {
    command -v quickshell >/dev/null 2>&1 || return 1
    local payload
    payload=$(jq -cn --arg t "$TITLE" --arg b "$BODY" --arg g "$GLYPH" \
        '{title:$t, body:$b, glyph:$g}') || return 1
    # `summon` prints "ok" on success and "unknown" if the plugin is not
    # registered; a dead shell makes the call itself fail.
    local out
    out=$(timeout 3 quickshell ipc -p "$HOME/.config/quickshell" \
        call shell summon panel.alert "$payload" 2>/dev/null) || return 1
    [[ "$out" == *ok* ]]
}

play_sound

if ! show_card; then
    # Shell down, or the overlay unavailable: never drop the alert.
    "$(dirname "$(readlink -f "$0")")/notification-send.sh" -g "$GLYPH" "$TITLE" "$BODY" || true
fi
