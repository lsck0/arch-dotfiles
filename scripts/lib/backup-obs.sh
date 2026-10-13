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
# only guard once a live scene exists; no scene yet is nothing to back up
[ -e "${SCENE}" ] && secret_seed_guard "${MARKER}" "${REPO}/secrets/obs-Untitled.json" "${SCENE}"

# the obs module's link.sh links these files into the repo; obs replaces a link with a plain file on save
modules=("${REPO}"/configs/*/obs)
MODULE=${modules[0]}
[ -d "${MODULE}" ] || { echo "no configs/<group>/obs module" >&2; exit 1; }

backup() {
    [ -e "$1" ] || return 0
    [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ] && return 0
    cp -f "$1" "$2"
}

backup "${SCENE}" "${REPO}/secrets/obs-Untitled.json"
backup "${HOME}/.config/obs-studio/basic/profiles/Streaming/service.json" "${REPO}/secrets/obs-service.json"

# each repo-owned profile's non-secret files back into the module; service.json stays out, it is the stream key
for live in "${HOME}"/.config/obs-studio/basic/profiles/*/; do
    dest="${MODULE}/profiles/$(basename "${live}")"
    [ -d "${dest}" ] || continue
    for f in "${live}"basic.ini "${live}"*Encoder.json; do
        [ -e "$f" ] || continue
        out="${dest}/$(basename "$f")"
        # strip the per-platform render node link.sh injected, so the repo copy stays machine-agnostic
        if [[ "$f" == *Encoder.json ]]; then
            jq 'del(.vaapi_device)' "$f" >"${out}" 2>/dev/null || backup "$f" "${out}"
        else
            backup "$f" "${out}"
        fi
    done
done
