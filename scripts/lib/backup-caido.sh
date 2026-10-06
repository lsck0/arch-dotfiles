#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# pull caido's plugin set (plugins.db + the plugins dir) into secrets/caido; configs/pentesting/caido/link.sh seeds a fresh install from it. projects, login token and settings stay out.

set -euo pipefail

REPO="$DOTFILES"
CAIDO="${HOME}/.local/share/caido"
DEST="${REPO}/secrets/caido"

source "${REPO}/scripts/lib/secrets.sh"

[ -f "${CAIDO}/plugins.db" ] || { echo "no ${CAIDO}/plugins.db" >&2; exit 1; }
secret_require_unlocked "${REPO}"

mkdir -p "${DEST}"
# a consistent copy even if caido is running, instead of rsyncing a half-written db
sqlite3 "${CAIDO}/plugins.db" ".backup '${DEST}/plugins.db'"
rsync -a --delete "${CAIDO}/plugins/" "${DEST}/plugins/"
