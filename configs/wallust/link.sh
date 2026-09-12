#!/usr/bin/env bash

set -ex

mkdir -p ${HOME}/.config/wallust
mkdir -p ${HOME}/.config/wallust/colorschemes

ln -sf ${PWD}/templates ${HOME}/.config/wallust/templates
ln -sf ${PWD}/wallust.toml ${HOME}/.config/wallust/wallust.toml

for theme in ${PWD}/../../themes/*.json; do
    [ -e "$theme" ] || continue
    ln -sf "$theme" "${HOME}/.config/wallust/colorschemes/$(basename "$theme")"
done
