#!/usr/bin/env bash
# konsole only runs as dolphin's terminal panel; give it the wallpaper palette and the system font
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v konsole >/dev/null 2>&1; then
    exit 0
fi

set -e

mkdir -p "${HOME}/.local/share/konsole"
ln -sfn "${PWD}/pywal.profile" "${HOME}/.local/share/konsole/pywal.profile"
# wallust renders this on every wallpaper switch (configs/wallust/templates/wal)
ln -sfn "${HOME}/.cache/wal/colors-konsole.colorscheme" "${HOME}/.local/share/konsole/pywal.colorscheme"
# konsole rewrites konsolerc with window state, so set only the key
kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile pywal.profile
