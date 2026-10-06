#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

mkdir -p "$HOME/.config/zathura" "$HOME/.cache/wal"
ln -sfn "${PWD}/zathurarc" "$HOME/.config/zathura/zathurarc"

# include does not expand ~, so link the palette beside zathurarc
[[ -e "$HOME/.cache/wal/colors-zathura" ]] || : > "$HOME/.cache/wal/colors-zathura"
ln -sfn "$HOME/.cache/wal/colors-zathura" "$HOME/.config/zathura/colors-zathura"
