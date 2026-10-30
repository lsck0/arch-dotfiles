# base/ssh dropped its own ssh-agent.service for openssh's socket-activated one. The old agent unlinks the socket path
# on exit, so it stops and its unit goes before the socket binds; the apply then finds the switch done, and ssh-add
# loads the key into the new agent.

use module.nu [unit-dir]

const SERVICE = "ssh-agent.service"
const SOCKET = "ssh-agent.socket"
const KEY_LOADER = "ssh-add.service"

export def up []: nothing -> nothing {
    let unit = unit-dir | path join $SERVICE
    if ($unit | path exists) {
        ^systemctl --user disable --now $SERVICE
        rm $unit
        ^systemctl --user daemon-reload
    }
    ^systemctl --user enable --now $SOCKET
    if (^systemctl --user is-enabled $KEY_LOADER | complete | get stdout | str trim) == "enabled" {
        ^systemctl --user start --no-block $KEY_LOADER
    }
}
