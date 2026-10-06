#!/usr/bin/env bash
# pull ffxiv game, character and xivlauncher settings into configs/base/secrets/ffxiv; configs/gaming/ffxiv/link.sh restores them

set -euo pipefail

REPO="${HOME}/projects/arch-dotfiles"
XLCORE="${HOME}/.xlcore"
# character folders are named after the content id and the DATs hold macros and gearsets, so they live in secrets
DEST="${REPO}/configs/base/secrets/ffxiv"

source "${REPO}/scripts/lib/secrets.sh"

[ -f "${XLCORE}/ffxivConfig/FFXIV.cfg" ] || { echo "no ${XLCORE}/ffxivConfig/FFXIV.cfg" >&2; exit 1; }
secret_require_unlocked "${REPO}"

mkdir -p "${DEST}"
# system cfgs plus each character's DATs; chat logs, game backups, screenshots and .old rotations stay out
rsync -a --delete --prune-empty-dirs \
    --include 'FFXIV*.cfg' --include 'FFXIV_CHR*/' --include 'FFXIV_CHR*/*.DAT' --exclude '*' \
    "${XLCORE}/ffxivConfig/" "${DEST}/ffxivConfig/"
# the account id is the square enix login; accounts.json (login and last otp) and the keyring password stay out
sed '/^CurrentAccountId=/d' "${XLCORE}/launcher.ini" >"${DEST}/launcher.ini"
