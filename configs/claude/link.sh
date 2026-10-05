#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/secrets.sh

if ! command -v claude >/dev/null 2>&1; then
    exit 0
fi

set -e

SETTINGS="${HOME}/.claude/settings.json"

mkdir -p "${HOME}/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

ln -sfn "${PWD}/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
ln -sfn "${PWD}/RTK.md" "${HOME}/.claude/RTK.md"

# caido's vibe-hacking mcp server, so claude can drive the proxy; only connects once enabled in caido
if command -v caido >/dev/null 2>&1; then
    claude mcp remove caido -s user >/dev/null 2>&1 || true
    claude mcp add --transport http --scope user caido http://127.0.0.1:3333/mcp >/dev/null 2>&1 || true
fi

tmp=$(mktemp)
jq '. + {remoteControlAtStartup: true, model: "claude-opus-5-5", voice: {enabled: true, mode: "hold"}}
   | .modelSettings["claude-opus-5-5"].effortLevel = "high"
   | .hooks = ((.hooks // {}) + {
       "UserPromptSubmit": [{"hooks":[{"type":"command","command":"~/.config/hypr/claude-sleep-guard.sh acquire"}]}],
       "Stop":            [{"hooks":[{"type":"command","command":"~/.config/hypr/claude-sleep-guard.sh release"}]}],
       "SessionEnd":      [{"hooks":[{"type":"command","command":"~/.config/hypr/claude-sleep-guard.sh release"}]}]
     })' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS"
rm -f "$tmp"

# login backed up by scripts/backup-claude.sh; only a home that is not logged in yet is seeded
BACKUP="$(readlink -f ../secrets/claude)"
if secret_is_plaintext "${BACKUP}/credentials.json" && [ ! -f "${HOME}/.claude/.credentials.json" ]; then
    umask 077
    cp "${BACKUP}/credentials.json" "${HOME}/.claude/.credentials.json"
    [ -f "${HOME}/.claude.json" ] || echo '{}' > "${HOME}/.claude.json"
    tmp=$(mktemp)
    jq -s '.[0] + .[1]' "${HOME}/.claude.json" "${BACKUP}/account.json" > "$tmp"
    cat "$tmp" > "${HOME}/.claude.json"
    rm -f "$tmp"
fi
