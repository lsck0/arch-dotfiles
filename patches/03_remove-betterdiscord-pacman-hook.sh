#!/usr/bin/env bash
# drop the betterdiscordctl pacman hook: the discord package is only an updater bootstrap, configs/socials/discord's path unit injects now; pacman/link.sh never removes a hook

set -euo pipefail

HOOK=/etc/pacman.d/hooks/betterdiscord-reinject.hook

[[ -e "$HOOK" ]] || exit 0
sudo rm -f "$HOOK"
