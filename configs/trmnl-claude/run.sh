#!/usr/bin/env bash
# post this machine's claude code usage to the trmnl plugin
set -euo pipefail
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
ENV_FILE="$DIR/../secrets/trmnl-claude.env"

[ -r "$ENV_FILE" ] || { echo "missing $ENV_FILE (TRMNL_PLUGIN_UUID=...)" >&2; exit 1; }
# a timer gets a bare PATH
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
set -a; . "$ENV_FILE"; set +a

# headers: auto drives a claude tui for 20 s (11 s cpu) every run for a per-model row max plans lack
exec python3 "$DIR/claude_trmnl.py" --usage-method headers "$@"
