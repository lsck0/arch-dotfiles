#!/usr/bin/env bash
# Pull Dalamud's config, plugin configs and plugin manifests from ~/.xlcore into configs/secrets/dalamud;
# configs/dalamud/link.sh downloads the plugins again from those manifests.

set -euo pipefail
shopt -s nullglob

REPO="${HOME}/projects/arch-dotfiles"
XLCORE="${HOME}/.xlcore"
# plugin configs carry character names and content ids, so they live in secrets
DEST="${REPO}/configs/secrets/dalamud"

source "${REPO}/scripts/lib/secrets.sh"

[ -f "${XLCORE}/dalamudConfig.json" ] || { echo "no ${XLCORE}/dalamudConfig.json" >&2; exit 1; }
# a locked worktree holds GITCRYPT blobs; writing plaintext into it would stage secrets unencrypted
secret_is_plaintext "${REPO}/configs/secrets/pgp_privatekey.asc" \
    || { echo "configs/secrets is locked, unlock it first" >&2; exit 1; }

mkdir -p "${DEST}"
cp -f "${XLCORE}/dalamudConfig.json" "${XLCORE}/dalamudUI.ini" "${DEST}/"
# caches and recordings the plugins rebuild or download: vnavmesh alone is 500+ MiB
rsync -a --delete \
    --exclude 'vnavmesh/meshcache/' \
    --exclude 'BossMod/replays/' \
    --exclude 'Questionable/PathData/' \
    --exclude '*.bak' \
    "${XLCORE}/pluginConfigs/" "${DEST}/pluginConfigs/"

# the manifest of each installed plugin's newest version: source repo and collection id for configs/dalamud/link.sh
rm -rf "${DEST}/manifests" "${DEST}/plugins.txt"
mkdir -p "${DEST}/manifests"
for dir in "${XLCORE}"/installedPlugins/*/; do
    name=$(basename "${dir}")
    version=$(find "${dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)
    if [ -f "${dir}${version}/${name}.json" ]; then
        cp "${dir}${version}/${name}.json" "${DEST}/manifests/"
    fi
done
