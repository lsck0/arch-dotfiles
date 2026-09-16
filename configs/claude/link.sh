#!/usr/bin/env bash

if ! command -v claude >/dev/null 2>&1; then
    exit 0
fi

set -ex

SETTINGS="${HOME}/.claude/settings.json"

mkdir -p "${HOME}/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

tmp=$(mktemp)
jq '. + {remoteControlAtStartup: true}' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS"
rm -f "$tmp"
