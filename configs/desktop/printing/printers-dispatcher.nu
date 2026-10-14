#!/usr/bin/nu --no-config-file
# after 90-anonymous-persona started avahi; a unit, not inline: discovery takes seconds and dispatchers run serially

const HOME_NETWORK = "/run/home-network"

def main [iface: string = "", action: string = "", ...rest: string]: nothing -> nothing {
    if $action != "up" { return }
    let home = try { open --raw $HOME_NETWORK | lines } catch { [] }
    if $iface not-in $home { return }
    ^systemctl start --no-block printers-sync.service
}
