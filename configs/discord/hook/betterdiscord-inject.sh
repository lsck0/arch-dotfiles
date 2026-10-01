#!/usr/bin/env bash
# inject betterdiscord into the newest discord build; discord churns files here, so the injected check comes first
# no betterdiscordctl: it hardcodes discord_desktop_core-1, and discord ships -2 and up

set -euo pipefail

ASAR="${HOME}/.config/BetterDiscord/data/betterdiscord.asar"
ASAR_URL=https://github.com/BetterDiscord/BetterDiscord/releases/latest/download/betterdiscord.asar

modules=$(find "${HOME}/.config/discord" -maxdepth 3 -type d -name 'discord_desktop_core-*' 2>/dev/null | sort -V | tail -n 1)
[[ -n "$modules" ]] || exit 0
index="${modules}/discord_desktop_core/index.js"
[[ -f "$index" ]] || exit 0
grep -q betterdiscord "$index" && [[ -f "$ASAR" ]] && exit 0

# download to tmp then mv, so a cut connection never leaves a truncated asar for discord to load
mkdir -p "$(dirname "$ASAR")"
curl -fsSL --retry 3 -m 120 -o "${ASAR}.tmp" "$ASAR_URL"
mv "${ASAR}.tmp" "$ASAR"

# the same two lines the official installer writes
printf 'require("%s");\nmodule.exports = require("./core.asar");\n' "$ASAR" >"$index"
