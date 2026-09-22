#!/usr/bin/env bash
# Post this machine's Claude Code usage to the TRMNL plugin.
#
# The plugin UUID is a write token for the display: anyone holding it can post
# whatever they like to it. arch-dotfiles is public, so it lives in the private
# secrets submodule instead, and only ever reaches this script through the
# environment.
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ENV_FILE="$DIR/../secrets/trmnl-claude.env"

[ -r "$ENV_FILE" ] || { echo "missing $ENV_FILE (TRMNL_PLUGIN_UUID=...)" >&2; exit 1; }
# a timer gets a bare PATH
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
set -a; . "$ENV_FILE"; set +a

exec python3 "$DIR/claude_trmnl.py" "$@"
