#!/usr/bin/env bash
# Pull the live OBS scene and profile from ~/.config/obs-studio back into the repo.

set -ex

cp ${HOME}/.config/obs-studio/basic/scenes/Untitled.json ${HOME}/projects/arch-dotfiles/configs/secrets/obs-Untitled.json
cp ${HOME}/.config/obs-studio/basic/profiles/Untitled/basic.ini ${HOME}/projects/arch-dotfiles/configs/obs/basic.ini
