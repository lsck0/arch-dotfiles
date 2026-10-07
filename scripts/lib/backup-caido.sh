#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# pull caido's plugin set (plugins.db, the plugins dir and each plugin's data.db) into secrets/caido; configs/pentesting/caido/link.sh seeds a fresh install from it. projects, per-project plugin data, login token and settings stay out.

set -euo pipefail

REPO="$DOTFILES"
CAIDO="${HOME}/.local/share/caido"
DEST="${REPO}/secrets/caido"

source "${REPO}/scripts/lib/secrets.sh"

[ -f "${CAIDO}/plugins.db" ] || { echo "no ${CAIDO}/plugins.db" >&2; exit 1; }
secret_require_unlocked "${REPO}"
MARKER="${CAIDO}/.from-secrets"
if [ ! -e "${MARKER}" ]; then
    [ -e "${DEST}/plugins.db" ] && { echo "${CAIDO} was not seeded from secrets; run config.sh, or touch ${MARKER} to keep the live state" >&2; exit 1; }
    touch "${MARKER}"
fi

mkdir -p "${DEST}"
# a consistent copy even if caido is running; .backup into an old copy bumps its change counter, so every sync would commit a new blob
rm -f "${DEST}/plugins.db"
sqlite3 "${CAIDO}/plugins.db" ".backup '${DEST}/plugins.db'"
rsync -a --delete --exclude 'sessions/' --exclude 'projects/' --exclude 'crawler-job*' --exclude 'data.db*' \
    --exclude '*-wal' --exclude '*-shm' --exclude '*-journal' \
    "${CAIDO}/plugins/" "${DEST}/plugins/"
for db in "${CAIDO}"/plugins/*/data.db; do
    [ -f "${db}" ] || continue
    copy="${DEST}/plugins/$(basename "$(dirname "${db}")")/data.db"
    rm -f "${copy}"
    sqlite3 "${db}" ".backup '${copy}'"
done
