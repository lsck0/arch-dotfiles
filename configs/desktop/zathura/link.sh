#!/usr/bin/env bash

link_into "$HOME/.config/zathura" zathurarc

# include does not expand ~, so link the palette beside zathurarc
mkdir -p "$HOME/.cache/wal"
[[ -e "$HOME/.cache/wal/colors-zathura" ]] || : >"$HOME/.cache/wal/colors-zathura"
ln -sfn "$HOME/.cache/wal/colors-zathura" "$HOME/.config/zathura/colors-zathura"
