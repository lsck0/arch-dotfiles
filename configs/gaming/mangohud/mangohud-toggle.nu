#!/usr/bin/env -S nu --no-config-file
# flips the hud of every running game through its control socket (MangoHud.conf control=mangohud-%p)

const SOCKET_PREFIX = "@mangohud-"
const COMMAND_HUD = ":hud;"

def main []: nothing -> nothing {
    let sockets = open --raw /proc/net/unix | lines | skip 1 | each { split row " " | last }
        | where { str starts-with $SOCKET_PREFIX } | uniq
    for socket in $sockets {
        $COMMAND_HUD | ^socat -u - $"ABSTRACT-CONNECT:($socket | str substring 1..)" | complete | ignore
    }
}
