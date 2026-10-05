#!/usr/bin/env bash
# first spicetify apply once spotify is logged in; later spotify updates go through the pacman hook

set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../../../scripts/lib/user-hook.sh"

PREFS="${HOME}/.config/spotify/prefs"

grep -q '^autologin.username' "$PREFS" 2>/dev/null || exit 0
if [[ ! -d /opt/spotify/Apps/xpui ]]; then
    spicetify backup apply
    spicetify enable-devtools
    python3 "$(dirname "$(readlink -f "$0")")/../spicetify-unmap-classes.py"
fi

user_hook_retire spicetify-apply
