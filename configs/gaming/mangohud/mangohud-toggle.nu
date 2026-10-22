#!/usr/bin/env -S nu --no-config-file
# flips the hud of the focused window's game through its control socket (MangoHud.conf control=mangohud-%p);
# --all flips every running game's hud instead (the old behavior, kept as an escape hatch)

const SOCKET_PREFIX = "@mangohud-"
const COMMAND_HUD = ":hud;"

def sockets []: nothing -> list<string> {
    open --raw /proc/net/unix | lines | skip 1 | each { split row " " | last }
    | where { str starts-with $SOCKET_PREFIX } | uniq
}

# a dead game can leave its abstract socket name lingering with nothing accepting on it; bound the write so
# that one stale entry can't hang every other running game's toggle behind it
def send [socket: string]: nothing -> nothing {
    $COMMAND_HUD | ^timeout 2 socat -u - $"ABSTRACT-CONNECT:($socket | str substring 1..)" | complete | ignore
}

# the focused window's pid, when a compositor is up to ask (hyprctl absent or no answer -> no pid)
def focused-socket []: nothing -> string {
    let pid = try { ^hyprctl activewindow -j | from json | get pid } catch { return "" }
    $"($SOCKET_PREFIX)($pid)"
}

def main [--all]: nothing -> nothing {
    let live = sockets
    let target = if $all { "" } else { focused-socket }
    # no focused game's socket (unfocused, alt-tabbed away, hyprctl unavailable) -> fall back to every running one
    let picked = if ($target | is-empty) or $target not-in $live { $live } else { [$target] }
    for socket in $picked { send $socket }
}
