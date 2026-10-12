#!/usr/bin/env bash
# extract the newest Bridge and Fab plugin zips from ~/sync/vendor into the engine; idempotent, rerun after an engine update.
# the install hook runs it after every engine install; the engine is the user's own, so no root
set -euo pipefail

ENGINE="${XDG_DATA_HOME:-${HOME}/.local/share}/unreal-engine"
SYNC_DIR="${HOME}/sync/vendor"
STAMP_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/unreal-plugins"

[[ -d "$ENGINE" ]] || exit 0
mkdir -p "$STAMP_DIR"

for plugin in Bridge Fab; do
    # a stamp mismatch or the plugin dir gone (a fresh engine install) re-triggers the extract
    zips=("${SYNC_DIR}"/Linux_"${plugin}"_*.zip)
    [[ -e "${zips[0]}" ]] || continue
    zip=$(printf '%s\n' "${zips[@]}" | sort -V | tail -1)
    stamp="${STAMP_DIR}/${plugin}"
    if [[ "$(cat "$stamp" 2>/dev/null)" == "$zip" && -d "${ENGINE}/Engine/Plugins/${plugin}" ]]; then
        continue
    fi
    echo "unreal: installing ${plugin} from $(basename "$zip")" >&2
    unzip -oq "$zip" -d "$ENGINE"
    echo "$zip" >"$stamp"
done
