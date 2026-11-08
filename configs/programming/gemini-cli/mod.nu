use module.nu *

# after idle-guards: the guard hooks go in only once its agent-guard exists; as an input the guard appearing re-plans them
export const meta = {
    deps: [desktop/idle-guards]
    packages: {pacman: [gemini-cli]}
    inputs: [~/.config/idle-guards/agent-guard.nu]
}

use ../../desktop/idle-guards/mod.nu [AGENT_GUARD]

# gemini runs a hook as `bash -c <command>`, which execs the guard, so the guard's parent is gemini itself. A tool
# approved at a permission prompt resumes the turn with no new prompt, so AfterTool re-arms it (BeforeTool is rtk's).
const GUARD_EVENTS = {BeforeAgent: turn-start, AfterTool: turn-start, AfterAgent: turn-end, Notification: turn-end, SessionEnd: turn-end}

# Each guard event's hook groups: the ones others put there, then the guard's while it exists.
def guard-hooks [settings: path]: nothing -> list<record> {
    let guard = $nu.home-dir | path join $AGENT_GUARD
    let current = try { open $settings | get --optional hooks | default {} } catch { {} }
    $GUARD_EVENTS | items {|event, action|
        let kept = $current | get --optional $event | default []
            | where {|g| not ($g.hooks? | default [] | any { $in.command? | default "" | str contains agent-guard }) }
        let own = if ($guard | path exists) { [{hooks: [{type: command, name: agent-guard, command: $"($guard) ($action)"}]}] } else { [] }
        let groups = $kept ++ $own
        if ($groups | is-empty) { json-delete [hooks $event] } else { json-set [hooks $event] $groups }
    }
}

export def link [cfg: record] {
    let settings = $nu.home-dir | path join .gemini settings.json
    json-merge $settings ([
        (json-set [privacy usageStatisticsEnabled] false)
        (json-set [telemetry enabled] false)
    ] ++ (guard-hooks $settings))
}
