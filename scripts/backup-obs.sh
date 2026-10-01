#!/usr/bin/env bash
# Pull the live OBS scene and profile from ~/.config/obs-studio back into the repo.

set -ex

# configs/obs/link.sh links both files into the repo; obs replaces a link with a plain file on save
backup() {
    [ -e "$1" ] || return 0
    [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ] && return 0
    cp -f "$1" "$2"
}

backup ${HOME}/.config/obs-studio/basic/scenes/Untitled.json ${HOME}/projects/arch-dotfiles/configs/secrets/obs-Untitled.json
backup ${HOME}/.config/obs-studio/basic/profiles/Untitled/basic.ini ${HOME}/projects/arch-dotfiles/configs/obs/basic.ini
