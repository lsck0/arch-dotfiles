#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/secrets.sh

set -e

SETTINGS="${HOME}/.claude/settings.json"

mkdir -p "${HOME}/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

ln -sfn "${PWD}/CLAUDE.md" "${HOME}/.claude/CLAUDE.md"
ln -sfn "${PWD}/RTK.md" "${HOME}/.claude/RTK.md"

# awake only while an agent works: a turn in flight or a subagent running; waiting on the user releases it
guard="$HOME/.config/idle-guards/agent-guard.sh"
hook() { jq -n --arg c "$guard $1" '[{hooks: [{type: "command", command: $c}]}]'; }
hooks='{}'
if [ -x "$guard" ]; then
    hooks=$(jq -n --argjson start "$(hook turn-start)" --argjson end "$(hook turn-end)" \
        --argjson sub_start "$(hook subagent-start)" --argjson sub_stop "$(hook subagent-stop)" \
        '{UserPromptSubmit: $start, Stop: $end, StopFailure: $end, SessionEnd: $end,
          Notification: [{matcher: "idle_prompt|permission_prompt|agent_needs_input|elicitation_dialog", hooks: $end[0].hooks}],
          SubagentStart: $sub_start, SubagentStop: $sub_stop}')
fi
tmp=$(mktemp)
jq --argjson guard_hooks "$hooks" '. + {remoteControlAtStartup: true, model: "claude-opus-5-5", voice: {enabled: true, mode: "hold"}}
   | .modelSettings["claude-opus-5-5"].effortLevel = "medium"
   | .hooks = ((.hooks // {}) + $guard_hooks)' "$SETTINGS" > "$tmp"
cat "$tmp" > "$SETTINGS"
rm -f "$tmp"

# login backed up by scripts/backup-claude.sh; only a home that is not logged in yet is seeded
BACKUP="$(readlink -f $DOTFILES/secrets/claude)"
if secret_is_plaintext "${BACKUP}/credentials.json" && [ ! -f "${HOME}/.claude/.credentials.json" ]; then
    umask 077
    cp "${BACKUP}/credentials.json" "${HOME}/.claude/.credentials.json"
    [ -f "${HOME}/.claude.json" ] || echo '{}' > "${HOME}/.claude.json"
    tmp=$(mktemp)
    jq -s '.[0] + .[1]' "${HOME}/.claude.json" "${BACKUP}/account.json" > "$tmp"
    cat "$tmp" > "${HOME}/.claude.json"
    rm -f "$tmp"
fi
