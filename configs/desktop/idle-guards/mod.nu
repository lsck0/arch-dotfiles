use module.nu *

export const meta = {packages: {pacman: [playerctl]}}

const SCRIPTS = [agent-guard.nu media-guard.nu ssh-guard.nu]
# each unit runs <guard>-guard.nu; the agent guard runs from the agents' hooks instead
const UNITS = [
    [guard unit while];
    [media idle-guard-media.service "media plays"]
    [ssh idle-guard-ssh.service "an ssh session is open"]
]
export const AGENT_GUARD = ".config/idle-guards/agent-guard.nu"
# an agent module's meta input: the guard appearing re-plans its hooks
export const AGENT_GUARD_INPUT = $"~/($AGENT_GUARD)"

# A hook entry, or one hook, that runs the guard: an entry nests its hooks, a hook carries the command itself.
export def guard-hook []: record -> bool {
    [$in] ++ ($in.hooks? | default []) | any { $in.command? | default "" | str contains agent-guard }
}

export def system [cfg: record] {
    file-copy 49-idle-guards.rules /etc/polkit-1/rules.d/49-idle-guards.rules
}

export def link [cfg: record] {
    let dir = xdg config idle-guards
    [
        ($SCRIPTS | each {|script| file-copy $script ($dir | path join $script) --mode 755 })
        ($UNITS | each {|u|
            [
                (file-render idle-guard.service (unit-dir | path join $u.unit) {GUARD: $u.guard, WHILE: $u.while})
                (unit-enable $u.unit)
            ]
        })
    ]
}
