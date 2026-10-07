#!/usr/bin/env bash
: "${DOTFILES:=$HOME/projects/arch-dotfiles}"
# pull Dalamud's config, plugin configs and plugin manifests from ~/.xlcore into secrets/dalamud; configs/gaming/dalamud/link.sh downloads the plugins again from those manifests

set -euo pipefail
shopt -s nullglob

REPO="$DOTFILES"
XLCORE="${HOME}/.xlcore"
# plugin configs carry character names and content ids, so they live in secrets
DEST="${REPO}/secrets/dalamud"

source "${REPO}/scripts/lib/secrets.sh"

[ -f "${XLCORE}/dalamudConfig.json" ] || { echo "no ${XLCORE}/dalamudConfig.json" >&2; exit 1; }
secret_require_unlocked "${REPO}"
MARKER="${XLCORE}/.dalamud-from-secrets"
if [ ! -e "${MARKER}" ]; then
    [ -e "${DEST}/dalamudConfig.json" ] && { echo "${XLCORE} was not seeded from secrets; run config.sh, or touch ${MARKER} to keep the live state" >&2; exit 1; }
    touch "${MARKER}"
fi

mkdir -p "${DEST}"
cp -f "${XLCORE}/dalamudConfig.json" "${XLCORE}/dalamudUI.ini" "${DEST}/"
# caches and recordings the plugins rebuild or download: vnavmesh alone is 500+ MiB
rsync -a --delete \
    --exclude 'vnavmesh/meshcache/' \
    --exclude 'BossMod/replays/' \
    --exclude 'Questionable/PathData/' \
    --exclude '*.bak' \
    "${XLCORE}/pluginConfigs/" "${DEST}/pluginConfigs/"

# the manifest of each installed plugin's newest version: source repo and collection id for configs/gaming/dalamud/link.sh
mkdir -p "${DEST}/manifests"
for dir in "${XLCORE}"/installedPlugins/*/; do
    name=$(basename "${dir}")
    version=$(find "${dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)
    if [ -f "${dir}${version}/${name}.json" ]; then
        cp "${dir}${version}/${name}.json" "${DEST}/manifests/"
    fi
done
