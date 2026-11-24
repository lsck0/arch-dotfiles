use module.nu *

export const meta = {packages: {pacman: [libpulse playerctl]}}

export const options = {
    guards: {
        type: list<string>
        default: [media mic ssh]
        choices: [media mic ssh]
        doc: "What holds off sleep: media (a player plays), mic (a microphone records), ssh (an ssh session is open)"
        label: "Sleep guards"
        scope: user
    }
}

const SCRIPTS = [agent-guard.nu sleep-guard.nu]
# each unit runs sleep-guard.nu <guard> (the agent guard runs from the agents' hooks instead); unit names stay literal
# for the ledger
const UNITS = [
    [guard unit while];
    [media idle-guard-media.service "media plays"]
    [mic idle-guard-mic.service "a microphone records"]
    [ssh idle-guard-ssh.service "an ssh session is open"]
]
export const AGENT_GUARD = ".config/idle-guards/agent-guard.nu"
# an agent module's meta input: the guard appearing re-plans its hooks
export const AGENT_GUARD_INPUT = $"~/($AGENT_GUARD)"

# A hook entry, or one hook, that runs the guard: an entry nests its hooks, a hook carries the command itself.
export def guard-hook []: record -> bool {
    [$in] ++ ($in.hooks? | default []) | any { $in.command? | default "" | str contains agent-guard }
}

export def link [cfg: record] {
    let dir = xdg config idle-guards
    [
        ($SCRIPTS | each {|script| file-copy $"scripts/($script)" ($dir | path join $script) --mode 755 })
        ($UNITS | where guard in $cfg.guards | each {|u|
            unit-file services/idle-guard.service --name $u.unit --values {GUARD: $u.guard, WHILE: $u.while} --enable
        })
    ]
}

export def system [cfg: record] {
    polkit-rules config/49-idle-guards.rules
}
