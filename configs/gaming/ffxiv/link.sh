#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../../scripts/lib/secrets.sh

# written by scripts/backup-ffxiv.sh; dalamud and its plugins are configs/gaming/dalamud
BACKUP="$(readlink -f ../../base/secrets/ffxiv)"
XLCORE="${HOME}/.xlcore"

# skip while XIVLauncher is not installed, or the secrets backup is locked
command -v xivlauncher-core >/dev/null 2>&1 || exit 0
secret_is_plaintext "${BACKUP}/launcher.ini" || exit 0

set -e

# copies, not links: the game and launcher rewrite these in place of a symlink. only a fresh ~/.xlcore is seeded
if [ ! -f "${XLCORE}/ffxivConfig/FFXIV.cfg" ]; then
    mkdir -p "${XLCORE}/ffxivConfig"
    cp -rT "${BACKUP}/ffxivConfig" "${XLCORE}/ffxivConfig"
fi
if [ ! -f "${XLCORE}/launcher.ini" ]; then
    cp "${BACKUP}/launcher.ini" "${XLCORE}/launcher.ini"
fi
