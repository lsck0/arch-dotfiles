#!/usr/bin/env bash
# inject betterdiscord into the running discord host's newest core; runs on every module change, so the injected check comes first
# no betterdiscordctl: it hardcodes discord_desktop_core-1, and discord ships -2 and up

set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/../../../../scripts/lib/fetch.sh"

ASAR="${HOME}/.config/BetterDiscord/data/betterdiscord.asar"
# runs inside discord with the account token, so a pinned release; bump both together
ASAR_URL=https://github.com/BetterDiscord/BetterDiscord/releases/download/v1.14.1/betterdiscord.asar
ASAR_SHA256=8595fffc8a8339f01cdf80b4a34c641cb96cf567732c5227f5c4c6779edff6f6

HOST="${HOME}/.config/discord/Discord"
# the path unit watches this; it follows the host the updater switches to, whose modules dir gets each core update
MODULES_LINK="${HOME}/.local/state/betterdiscord-modules"

[[ -e "$HOST" ]] || exit 0
modules_dir="$(dirname "$(readlink -f "$HOST")")/modules"
mkdir -p "$(dirname "$MODULES_LINK")"
ln -sfn "$modules_dir" "$MODULES_LINK"

core=$(find "$modules_dir" -maxdepth 1 -type d -name 'discord_desktop_core-*' | sort -V | tail -n 1)
[[ -n "$core" ]] || exit 0
index="${core}/discord_desktop_core/index.js"
[[ -f "$index" ]] || exit 0
asar_current() { [[ -f "$ASAR" ]] && sha256sum --quiet -c <<<"$ASAR_SHA256  $ASAR"; }
asar_current && grep -q betterdiscord "$index" && exit 0
asar_current || fetch_pinned "$ASAR_URL" "$ASAR_SHA256" "$ASAR"

# the same two lines the official installer writes
printf 'require("%s");\nmodule.exports = require("./core.asar");\n' "$ASAR" >"$index"
