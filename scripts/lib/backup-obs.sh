#!/usr/bin/env bash
# Pull the live OBS scene and profile from ~/.config/obs-studio back into the repo.

set -euo pipefail

REPO="${HOME}/projects/arch-dotfiles"
source "${REPO}/scripts/lib/secrets.sh"
# the scene collection holds stream tokens and lands in configs/base/secrets
secret_require_unlocked "${REPO}"

# configs/creating/obs/link.sh links both files into the repo; obs replaces a link with a plain file on save
backup() {
    [ -e "$1" ] || return 0
    [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ] && return 0
    cp -f "$1" "$2"
}

backup "${HOME}/.config/obs-studio/basic/scenes/Untitled.json" "${REPO}/configs/base/secrets/obs-Untitled.json"
backup "${HOME}/.config/obs-studio/basic/profiles/Untitled/basic.ini" "${REPO}/configs/creating/obs/basic.ini"
backup "${HOME}/.config/obs-studio/basic/profiles/Untitled/streamEncoder.json" "${REPO}/configs/creating/obs/streamEncoder.json"
backup "${HOME}/.config/obs-studio/basic/profiles/Untitled/recordEncoder.json" "${REPO}/configs/creating/obs/recordEncoder.json"
