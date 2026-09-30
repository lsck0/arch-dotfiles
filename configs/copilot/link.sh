#!/usr/bin/env bash

if ! command -v copilot >/dev/null 2>&1; then
    exit 0
fi

set -e

SETTINGS="${HOME}/.copilot/settings.json"

mkdir -p "${HOME}/.copilot"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

# /model in a session overwrites this key
tmp=$(mktemp)
jq '.model = "claude-sonnet-5"' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS"
rm -f "$tmp"
