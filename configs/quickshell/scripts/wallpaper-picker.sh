#!/usr/bin/env bash
# Native wallpaper picker: drives quickshell's image-picker overlay and applies whatever comes back.

# omarchy:summary=Pick a wallpaper from quickshell's image-picker overlay
# omarchy:args=[image-dir]
# omarchy:examples=wallpaper-picker.sh | wallpaper-picker.sh ~/Pictures

set -uo pipefail

# Two distinct pickable groups, toggled with Up/Down in the overlay: - WALLPAPERS (mode 0): photo wallpapers; selecting one auto-generates the palette via wallust (switch-wallpaper.sh).
SELF_DIR="$(dirname "$(readlink -f "$0")")"
# switch-wallpaper.sh stays repo-level: it is the colour engine for the whole desktop, not a quickshell helper.
SWITCH_WALLPAPER="$SELF_DIR/../../../scripts/switch-wallpaper.sh"

REPO_WALLPAPERS="$HOME/projects/arch-dotfiles/wallpapers"
THEMES_DIR="$HOME/projects/arch-dotfiles/themes"
DIR=${1:-$REPO_WALLPAPERS}
QS_CONFIG="$HOME/.config/quickshell"
RUN="${XDG_RUNTIME_DIR:-/tmp}"
SEL="$RUN/wallpaper-picker.selection.$$"
DONE="$RUN/wallpaper-picker.done.$$"

cleanup() { rm -f "$SEL" "$DONE"; }
trap cleanup EXIT

command -v quickshell >/dev/null 2>&1 || { echo "quickshell not installed" >&2; exit 1; }

# Open the carousel on whatever is currently set, rather than on the first file alphabetically.
CURRENT=$(readlink -f "$HOME/.cache/wal/wallpaper" 2>/dev/null || true)

# Pass the two groups SEPARATELY (imageDirs = photo wallpapers, themeDirs = the theme JSON directory).
PHOTO_DIRS="$DIR"

if ! timeout 3 quickshell ipc -p "$QS_CONFIG" call shell summon panel.image-picker \
        "$(jq -cn --arg d "$PHOTO_DIRS" --arg t "$THEMES_DIR" --arg s "$SEL" --arg f "$DONE" --arg c "$CURRENT" \
            '{imageDirs:$d, themeDirs:$t, mode:0, selectionFile:$s, doneFile:$f, selectedImage:$c, filterable:true, showLabels:true}')" \
        >/dev/null 2>&1; then
    # Shell down or the overlay unavailable — fall back to the fzf picker rather than leaving the user with nothing.
    echo "quickshell picker unavailable; falling back to the fzf picker" >&2
    exec "$SWITCH_WALLPAPER"
fi

: >"$SEL"

# Wait for the overlay to signal completion.
if command -v inotifywait >/dev/null 2>&1; then
    timeout 300 inotifywait -qq -e create -e close_write --include "$(basename "$DONE")" \
        "$(dirname "$DONE")" 2>/dev/null || true
else
    for _ in $(seq 1 600); do [[ -e "$DONE" ]] && break; sleep 0.5; done
fi

# A brief settle: the overlay writes <selection> and <done> in one shell command, but they are two separate writes.
for _ in $(seq 1 20); do [[ -s "$SEL" ]] && break; sleep 0.05; done

SELECTED=$(head -1 "$SEL" 2>/dev/null || true)
if [[ -z "$SELECTED" ]]; then
    echo "no wallpaper selected" >&2
    exit 0
fi
[[ -f "$SELECTED" ]] || { echo "selected file does not exist: $SELECTED" >&2; exit 1; }

exec "$SWITCH_WALLPAPER" set "$SELECTED"
