#!/usr/bin/env bash

if ! command -v copilot >/dev/null 2>&1; then
    exit 0
fi

set -ex

SETTINGS="${HOME}/.copilot/settings.json"

mkdir -p "${HOME}/.copilot"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# Default model sonnet-5, mirroring hermes (sonnet-5) and claude (opus-5-5).
# copilot writes this same "model" key itself when picked via /model in a session.
tmp=$(mktemp)
jq '.model = "claude-sonnet-5"' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS"
rm -f "$tmp"
