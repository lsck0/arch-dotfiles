#!/usr/bin/env bash

if ! command -v shimejictl >/dev/null 2>&1; then
    exit 0
fi

MARKER="$HOME/.local/state/shimoji-manual-link.done"
if [[ -e "$MARKER" ]]; then
    exit 0
fi

set -ex

cd "$(dirname "$0")"
ls *.wlshm | xargs -I {} shimejictl import {}

shimejictl config set BREEDING false

mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
