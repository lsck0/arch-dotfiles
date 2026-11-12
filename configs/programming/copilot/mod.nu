use module.nu *

# after idle-guards: the guard hooks go in only once its agent-guard exists; as an input the guard appearing re-plans them
export const meta = {
    deps: [desktop/idle-guards]
    packages: {pacman: [github-copilot-cli]}
    inputs: [~/.config/idle-guards/agent-guard.nu]
}

use ../../desktop/idle-guards/mod.nu [AGENT_GUARD]

# PascalCase events get the snake_case payload with the session_id the guard keys on. A permission prompt or the agent
# finishing notifies; a tool approved there resumes the turn with no new prompt, so every tool call re-arms it.
const GUARD_EVENTS = {
    UserPromptSubmit: turn-start PreToolUse: turn-start PostToolUse: turn-start Stop: turn-end Notification: turn-end
    SessionEnd: turn-end SubagentStart: subagent-start SubagentStop: subagent-stop
}

export def link [cfg: record] {
    let home = $nu.home-dir | path join .copilot
    let guard = $nu.home-dir | path join $AGENT_GUARD
    let hooks = $GUARD_EVENTS | items {|event, action| {$event: [{type: command, command: $"($guard) ($action)", timeout: 10}]} }
    [
        (json-merge ($home | path join settings.json) [(json-set [model] "claude-sonnet-5") (json-set [theme] "default")])
        # its own file in copilot's hook dir, next to rtk's
        (if ($guard | path exists) {
            file-text ($home | path join hooks agent-guard.json) ({version: 1, hooks: ($hooks | into record)} | to json --indent 2)
        } else { [] })
    ]
}
