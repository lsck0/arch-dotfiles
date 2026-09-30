#!/usr/bin/env bash
# first spicetify apply once spotify is logged in; later spotify updates go through the pacman hook

set -euo pipefail

PREFS="${HOME}/.config/spotify/prefs"

grep -q '^autologin.username' "$PREFS" 2>/dev/null || exit 0
[[ -d /opt/spotify/Apps/xpui ]] && exit 0

spicetify backup apply
spicetify enable-devtools
python3 "$(dirname "$(readlink -f "$0")")/../spicetify-unmap-classes.py"
