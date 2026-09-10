#!/usr/bin/env bash
# Pywal-themed dmenu-style picker. Reads newline-separated choices on stdin
# and prints the selection.
#
# Replaces `walker --dmenu`, which had two call sites (toggles/menu.sh and
# scripts/spawn-shimoji.sh) and was the reason walker could not be removed
# alongside the rest of it. quickshell's own launcher is an *application*
# launcher with no dmenu mode, so those call sites needed a real
# general-purpose picker rather than a shell IPC call.
#
# bemenu, not rofi/wofi/fuzzel: it is the only dmenu-style picker already
# installed here that has a Wayland backend
# (/usr/lib/bemenu/bemenu-renderer-wayland.so).
#
# Colours are read at call time from ~/.cache/wal/colors rather than baked
# into a config file, so this follows the wallpaper with no regeneration
# step — unlike walker, which needed switch-wallpaper.sh to rewrite its CSS
# on every wallpaper change. That sed block is gone with it.

# omarchy:summary=Pywal-themed dmenu-style chooser (bemenu)
# omarchy:args=[-p <prompt>] [extra bemenu args...]
# omarchy:examples=printf 'a\nb\n' | picker.sh -p "Pick one"

set -uo pipefail

WAL="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors"

c() { sed -n "$1p" "$WAL" 2>/dev/null; }

BG=$(c 1); FG=$(c 8); ACCENT=$(c 3); SEL_FG=$(c 1)
: "${BG:=#101010}" "${FG:=#d0d0d0}" "${ACCENT:=#5f87af}" "${SEL_FG:=#101010}"

FONT=$(sed -n 's/^font-family = //p' "$HOME/projects/arch-dotfiles/configs/ghostty/config" 2>/dev/null | head -1)
SIZE=$(sed -n 's/^font-size = //p' "$HOME/projects/arch-dotfiles/configs/ghostty/config" 2>/dev/null | head -1)
: "${FONT:=monospace}" "${SIZE:=14}"

exec bemenu \
    --ignorecase \
    --list 15 \
    --fn "$FONT $SIZE" \
    --tb "$BG" --tf "$ACCENT" \
    --fb "$BG" --ff "$FG" \
    --nb "$BG" --nf "$FG" \
    --hb "$ACCENT" --hf "$SEL_FG" \
    --scb "$BG" --scf "$ACCENT" \
    "$@"
