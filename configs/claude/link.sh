#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v claude >/dev/null 2>&1; then
    exit 0
fi

set -e

SETTINGS="${HOME}/.claude/settings.json"

mkdir -p "${HOME}/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

ln -sfn "${PWD}/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
ln -sfn "${PWD}/RTK.md" "${HOME}/.claude/RTK.md"

tmp=$(mktemp)
jq '. + {remoteControlAtStartup: true, model: "claude-opus-5-5"}
   | .modelSettings["claude-opus-5-5"].effortLevel = "high"
   | .hooks = ((.hooks // {}) + {
       "UserPromptSubmit": [{"hooks":[{"type":"command","command":"~/.config/hypr/claude-sleep-guard.sh acquire"}]}],
       "Stop":            [{"hooks":[{"type":"command","command":"~/.config/hypr/claude-sleep-guard.sh release"}]}],
       "SessionEnd":      [{"hooks":[{"type":"command","command":"~/.config/hypr/claude-sleep-guard.sh release"}]}]
     })' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS"
rm -f "$tmp"
