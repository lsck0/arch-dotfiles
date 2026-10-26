use module.nu *

export const meta = {packages: {pacman: [playerctl]}}

const GUARDS = [agent-guard.nu media-guard.nu ssh-guard.nu]
export const AGENT_GUARD = ".config/idle-guards/agent-guard.nu"

export def link [cfg: record] {
    let dir = xdg config idle-guards
    [
        ($GUARDS | each {|guard| file-copy $guard ($dir | path join $guard) --mode 755 })
        (unit-file idle-guard-media.service --enable)
        (unit-file idle-guard-ssh.service --enable)
    ]
}
