#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# Pull the live OBS scene and profile from ~/.config/obs-studio back into the repo.

set -euo pipefail

REPO="$DOTFILES"
source "${REPO}/scripts/lib/secrets.sh"
# the scene collection and the stream service hold stream tokens and land in secrets
secret_require_unlocked "${REPO}"

SCENE="${HOME}/.config/obs-studio/basic/scenes/Untitled.json"
MARKER="${HOME}/.config/obs-studio/basic/scenes/.from-secrets"
if [ -e "${SCENE}" ] && [ ! -e "${MARKER}" ]; then
    [ -e "${REPO}/secrets/obs-Untitled.json" ] && { echo "${SCENE} was not seeded from secrets; run config.sh, or touch ${MARKER} to keep the live state" >&2; exit 1; }
    touch "${MARKER}"
fi

# configs/creating/obs/link.sh links these files into the repo; obs replaces a link with a plain file on save
backup() {
    [ -e "$1" ] || return 0
    [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ] && return 0
    cp -f "$1" "$2"
}

backup "${SCENE}" "${REPO}/secrets/obs-Untitled.json"
backup "${HOME}/.config/obs-studio/basic/profiles/Untitled/service.json" "${REPO}/secrets/obs-service.json"
backup "${HOME}/.config/obs-studio/basic/profiles/Untitled/basic.ini" "${REPO}/configs/creating/obs/basic.ini"
backup "${HOME}/.config/obs-studio/basic/profiles/Untitled/streamEncoder.json" "${REPO}/configs/creating/obs/streamEncoder.json"
backup "${HOME}/.config/obs-studio/basic/profiles/Untitled/recordEncoder.json" "${REPO}/configs/creating/obs/recordEncoder.json"
