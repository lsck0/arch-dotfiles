#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v shimejictl >/dev/null 2>&1; then
    exit 0
fi

MARKER="$HOME/.local/state/shimoji-manual-link.done"

set -e

# settings are idempotent, apply every run; window interactions let mascots climb and sit on windows
shimejictl config set BREEDING false
shimejictl config set WINDOW_INTERACTIONS true

# importing the packs is the one-time part the marker guards
if [[ ! -e "$MARKER" ]]; then
    for pack in ./*.wlshm; do
        [ -e "$pack" ] || continue
        shimejictl import "$pack"
    done
    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"
fi
