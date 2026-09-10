#!/usr/bin/env bash
# Native wallpaper picker: drives quickshell's image-picker overlay and
# applies whatever comes back.
#
# The overlay (configs/quickshell/plugins/image-picker/) was ported in port
# Phase 6 and then sat unused for want of a consumer — it is Omarchy's
# general-purpose "pick from a directory of images" component, and its
# selection protocol is a file handshake designed for a shell caller:
#
#   caller  creates an empty <selection> file and names a <done> file
#   overlay on pick   -> writes the path to <selection>, then creates <done>
#           on cancel -> creates <done> and leaves <selection> empty
#
# Keeping that handshake in shell (rather than reimplementing it in the
# Display widget's QML) is why this is a script: it stays bindable to a key
# and usable without the bar, same as switch-wallpaper.sh.

# omarchy:summary=Pick a wallpaper from quickshell's image-picker overlay
# omarchy:args=[image-dir]
# omarchy:examples=wallpaper-picker.sh | wallpaper-picker.sh ~/Pictures

set -uo pipefail

# Two distinct pickable groups, toggled with Up/Down in the overlay:
#   - WALLPAPERS (mode 0): photo wallpapers; selecting one auto-generates the
#     palette via wallust (switch-wallpaper.sh).
#   - PREMADE THEMES (mode 1): the handwritten themes (themes/*.json, each
#     naming its own wallpaper via a "wallpaper" field); selecting one
#     applies the theme's hand-authored palette via wallust cs.
#     switch-wallpaper.sh matches the picked file against every theme
#     JSON's "wallpaper" field and uses that theme's colors.json instead of
#     deriving one.
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

# Open the carousel on whatever is currently set, rather than on the first
# file alphabetically.
CURRENT=$(readlink -f "$HOME/.cache/wal/wallpaper" 2>/dev/null || true)

# Pass the two groups SEPARATELY (imageDirs = photo wallpapers, themeDirs =
# the theme JSON directory). The overlay scans the active group's dir on its
# own and toggles between them with Up/Down. When the caller gave an explicit
# wallpaper dir, use only that for the wallpaper group; the theme group
# always points at THEMES_DIR regardless (it holds JSONs, not images).
PHOTO_DIRS="$DIR"

if ! timeout 3 quickshell ipc -p "$QS_CONFIG" call shell summon panel.image-picker \
        "$(jq -cn --arg d "$PHOTO_DIRS" --arg t "$THEMES_DIR" --arg s "$SEL" --arg f "$DONE" --arg c "$CURRENT" \
            '{imageDirs:$d, themeDirs:$t, mode:0, selectionFile:$s, doneFile:$f, selectedImage:$c, filterable:true, showLabels:true}')" \
        >/dev/null 2>&1; then
    # Shell down or the overlay unavailable — fall back to the fzf picker
    # rather than leaving the user with nothing.
    echo "quickshell picker unavailable; falling back to the fzf picker" >&2
    exec "$(dirname "$(readlink -f "$0")")/switch-wallpaper.sh"
fi

: >"$SEL"

# Wait for the overlay to signal completion. inotifywait rather than a poll
# loop so a slow browse costs nothing; the timeout is a safety net for an
# overlay that dies without ever writing <done>.
if command -v inotifywait >/dev/null 2>&1; then
    timeout 300 inotifywait -qq -e create -e close_write --include "$(basename "$DONE")" \
        "$(dirname "$DONE")" 2>/dev/null || true
else
    for _ in $(seq 1 600); do [[ -e "$DONE" ]] && break; sleep 0.5; done
fi

# A brief settle: the overlay writes <selection> and <done> in one shell
# command, but they are two separate writes.
for _ in $(seq 1 20); do [[ -s "$SEL" ]] && break; sleep 0.05; done

SELECTED=$(head -1 "$SEL" 2>/dev/null || true)
if [[ -z "$SELECTED" ]]; then
    echo "no wallpaper selected" >&2
    exit 0
fi
[[ -f "$SELECTED" ]] || { echo "selected file does not exist: $SELECTED" >&2; exit 1; }

exec "$(dirname "$(readlink -f "$0")")/switch-wallpaper.sh" set "$SELECTED"
