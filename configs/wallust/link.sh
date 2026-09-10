#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/wallust
ln -sf ${PWD}/wallust.toml ${HOME}/.config/wallust/wallust.toml
ln -sf ${PWD}/templates ${HOME}/.config/wallust/templates
# Handwritten palette themes (themes/*.json at repo root, pywal format).
# wallust `cs` matches scheme names FLAT in its colorschemes dir (no
# recursion), so each theme JSON is symlinked individually under its name.
# `wallust cs <name>` then regenerates ALL downstream templates (ghostty,
# kitty, tmux, hyprlock, colors.sh, colors-rgb), not just colors.json.
mkdir -p ${HOME}/.config/wallust/colorschemes
for theme in ${PWD}/../../themes/*.json; do
    [ -e "$theme" ] || continue
    ln -sf "$theme" "${HOME}/.config/wallust/colorschemes/$(basename "$theme")"
done
