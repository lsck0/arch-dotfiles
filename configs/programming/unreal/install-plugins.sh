#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# extract the newest Bridge and Fab plugin zips from ~/sync into the engine; idempotent, re-adds them after an engine update
command -v unzip >/dev/null 2>&1 || exit 0
engine=/opt/unreal-engine
[[ -d "$engine" ]] || exit 0

set -euo pipefail

sync_dir="${HOME}/sync"
stamp_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/unreal-plugins"
mkdir -p "$stamp_dir"

for plugin in Bridge Fab; do
    # the plugin's own dir carries the version, so a pacman engine reinstall that removes it re-triggers the extract
    zips=("${sync_dir}"/Linux_"${plugin}"_*.zip)
    [[ -e "${zips[0]}" ]] || continue
    zip=$(printf '%s\n' "${zips[@]}" | sort -V | tail -1)
    stamp="${stamp_dir}/${plugin}"
    if [[ "$(cat "$stamp" 2>/dev/null)" == "$zip" && -d "${engine}/Engine/Plugins/${plugin}" ]]; then
        continue
    fi
    echo "unreal: installing ${plugin} from $(basename "$zip")" >&2
    sudo unzip -oq "$zip" -d "$engine"
    echo "$zip" >"$stamp"
done
