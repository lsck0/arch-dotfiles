#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v shimejictl >/dev/null 2>&1; then
    exit 0
fi

MARKER="$HOME/.local/state/shimoji-manual-link.done"
if [[ -e "$MARKER" ]]; then
    exit 0
fi

set -ex

for pack in ./*.wlshm; do
    [ -e "$pack" ] || continue
    shimejictl import "$pack"
done

shimejictl config set BREEDING false

mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
