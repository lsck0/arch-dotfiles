#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# hand-dismissed alert card: <title> [body] [glyph] [kind: reminder|pomodoro] [snooze message]

set -uo pipefail

DOTFILES="${QS_DOTFILES_DIR:-$DOTFILES}"
REPO_SCRIPTS="$DOTFILES/scripts"

TITLE=${1:-Reminder}
BODY=${2:-}
GLYPH=${3:-$'\xf3\xb0\x80\xa0'}  # nerd font glyph as utf-8 bytes, the source stays ascii
# reminder can snooze, pomodoro can stop
KIND=${4:-}
SNOOZE_MESSAGE=${5:-}

SOUND=/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga

# foreground: the systemd unit kills background children on exit
play_sound() {
    if [[ -r "$SOUND" ]] && command -v pw-play >/dev/null 2>&1; then
        timeout 10 pw-play "$SOUND" >/dev/null 2>&1
    elif [[ -r "$SOUND" ]] && command -v paplay >/dev/null 2>&1; then
        timeout 10 paplay "$SOUND" >/dev/null 2>&1
    elif command -v canberra-gtk-play >/dev/null 2>&1; then
        timeout 10 canberra-gtk-play -i alarm-clock-elapsed >/dev/null 2>&1
    fi
    return 0
}

show_card() {
    command -v quickshell >/dev/null 2>&1 || return 1
    local payload
    payload=$(jq -cn --arg t "$TITLE" --arg b "$BODY" --arg g "$GLYPH" --arg k "$KIND" --arg m "$SNOOZE_MESSAGE" \
        '{title:$t, body:$b, glyph:$g, kind:$k, message:$m}') || return 1
    local out
    out=$(timeout 3 quickshell ipc -p "$HOME/.config/quickshell" \
        call shell summon panel.alert "$payload" 2>/dev/null) || return 1
    [[ "$out" == *ok* ]]
}

if ! show_card; then
    # never drop the alert
    "$REPO_SCRIPTS/lib/notification-send.sh" -g "$GLYPH" "$TITLE" "$BODY" || true
fi

play_sound
