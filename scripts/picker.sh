#!/usr/bin/env bash
# styled dmenu

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
