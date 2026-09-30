#!/usr/bin/env bash
# inject betterdiscord into the newest discord build; discord churns files here, so the injected check comes first

set -euo pipefail

modules=$(find "${HOME}/.config/discord" -maxdepth 3 -type d -name 'discord_desktop_core-*' 2>/dev/null | sort -V | tail -n 1)
[[ -n "$modules" ]] || exit 0
[[ -f "${modules}/discord_desktop_core/index.js" ]] || exit 0
grep -q betterdiscord "${modules}/discord_desktop_core/index.js" && exit 0

betterdiscordctl install || betterdiscordctl reinstall
