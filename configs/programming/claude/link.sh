#!/usr/bin/env bash

SETTINGS="${HOME}/.claude/settings.json"
# login backed up by scripts/lib/backup-claude.sh
BACKUP="${DOTFILES}/secrets/claude"

link_into "${HOME}/.claude" CLAUDE.md RTK.md

# awake only while an agent works: a turn in flight or a subagent running; waiting on the user releases it.
# a granted permission prompt resumes the turn without a new prompt, so every tool call re-arms it
guard="$HOME/.config/idle-guards/agent-guard.sh"
hook() { jq -n --arg c "$guard $1" '[{hooks: [{type: "command", command: $c}]}]'; }
hooks='{}'
if [ -x "$guard" ]; then
    hooks=$(jq -n --argjson start "$(hook turn-start)" --argjson end "$(hook turn-end)" \
        --argjson sub_start "$(hook subagent-start)" --argjson sub_stop "$(hook subagent-stop)" \
        '{UserPromptSubmit: $start, PreToolUse: $start, PostToolUse: $start, Stop: $end, StopFailure: $end, SessionEnd: $end,
          Notification: [{matcher: "idle_prompt|permission_prompt|agent_needs_input|elicitation_dialog", hooks: $end[0].hooks}],
          SubagentStart: $sub_start, SubagentStop: $sub_stop}')
fi
# only the guard's own hook entries are replaced, other hooks stay; a removed guard takes its stale ones along
json_update "$SETTINGS" --argjson guard_hooks "$hooks" \
    '. + {remoteControlAtStartup: true, model: "claude-opus-5-5", voice: {enabled: true, mode: "hold"}}
     | .modelSettings["claude-opus-5-5"].effortLevel = "medium"
     | .hooks = reduce ($guard_hooks | to_entries[]) as $e (
         .hooks // {} | map_values(map(select(any(.hooks[]?; .command // "" | contains("agent-guard")) | not)))
           | with_entries(select(.value != []));
         .[$e.key] += $e.value)'

# only a home that is not logged in yet is seeded
if secret_is_plaintext "${BACKUP}/credentials.json" && [ ! -f "${HOME}/.claude/.credentials.json" ]; then
    umask 077
    cp "${BACKUP}/credentials.json" "${HOME}/.claude/.credentials.json"
    json_update "${HOME}/.claude.json" --slurpfile account "${BACKUP}/account.json" '. + $account[0]'
fi
