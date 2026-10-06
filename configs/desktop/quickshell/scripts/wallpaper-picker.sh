#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# usage: [image-dir]

set -uo pipefail

DOTFILES="${QS_DOTFILES_DIR:-$DOTFILES}"
SWITCH_WALLPAPER="$DOTFILES/scripts/switch-wallpaper.sh"

REPO_WALLPAPERS="$DOTFILES/wallpapers"
THEMES_DIR="$DOTFILES/configs/base/themes"
DIR=${1:-$REPO_WALLPAPERS}
QS_CONFIG="$HOME/.config/quickshell"
RUN="${XDG_RUNTIME_DIR:-/tmp}"
SEL="$RUN/wallpaper-picker.selection.$$"
DONE="$RUN/wallpaper-picker.done.$$"

cleanup() { rm -f "$SEL" "$DONE"; }
trap cleanup EXIT

command -v quickshell >/dev/null 2>&1 || { echo "quickshell not installed" >&2; exit 1; }

# open on the current wallpaper
CURRENT=$(readlink -f "$HOME/.cache/wal/wallpaper" 2>/dev/null || true)

if ! timeout 3 quickshell ipc -p "$QS_CONFIG" call shell summon panel.image-picker \
        "$(jq -cn --arg d "$DIR" --arg t "$THEMES_DIR" --arg s "$SEL" --arg f "$DONE" --arg c "$CURRENT" \
            '{imageDirs:$d, themeDirs:$t, mode:0, selectionFile:$s, doneFile:$f, selectedImage:$c, filterable:true, showLabels:true}')" \
        >/dev/null 2>&1; then
    echo "quickshell picker unavailable; falling back to the fzf picker" >&2
    exec "$SWITCH_WALLPAPER"
fi

: >"$SEL"

if command -v inotifywait >/dev/null 2>&1; then
    timeout 300 inotifywait -qq -e create -e close_write --include "$(basename "$DONE")" \
        "$(dirname "$DONE")" 2>/dev/null || true
else
    for _ in $(seq 1 600); do [[ -e "$DONE" ]] && break; sleep 0.5; done
fi

# selection and done are two separate writes
for _ in $(seq 1 20); do [[ -s "$SEL" ]] && break; sleep 0.05; done

SELECTED=$(head -1 "$SEL" 2>/dev/null || true)
if [[ -z "$SELECTED" ]]; then
    echo "no wallpaper selected" >&2
    exit 0
fi
[[ -f "$SELECTED" ]] || { echo "selected file does not exist: $SELECTED" >&2; exit 1; }

exec "$SWITCH_WALLPAPER" set "$SELECTED"
