#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v nemo >/dev/null 2>&1; then
    exit 0
fi

set -ex

mkdir -p "${HOME}/.config/gtk-3.0"

# User-level override loaded after the oomox theme; see gtk.css header for why this survives palette regen.
ln -sfn "${PWD}/gtk.css" "${HOME}/.config/gtk-3.0/gtk.css"
