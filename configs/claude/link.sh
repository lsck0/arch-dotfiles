#!/usr/bin/env bash

if ! command -v claude >/dev/null 2>&1; then
    exit 0
fi

set -ex

SETTINGS="${HOME}/.claude/settings.json"

mkdir -p "${HOME}/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

tmp=$(mktemp)
# remoteControlAtStartup: RC on for every session (see it from the phone).
jq '. + {remoteControlAtStartup: true}
   | .hooks = ((.hooks // {}) + {
       "UserPromptSubmit": [{"hooks":[{"type":"command","command":"~/.config/hypr/claude-sleep-guard.sh acquire"}]}],
       "Stop":            [{"hooks":[{"type":"command","command":"~/.config/hypr/claude-sleep-guard.sh release"}]}],
       "SessionEnd":      [{"hooks":[{"type":"command","command":"~/.config/hypr/claude-sleep-guard.sh release"}]}]
     })' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS"
rm -f "$tmp"
