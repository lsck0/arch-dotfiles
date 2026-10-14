#!/usr/bin/nu --no-config-file
# NM dispatcher, after 90-anonymous-persona started avahi: a home link up queues the driverless printers found there.
# a unit, not inline: discovery takes seconds and dispatcher scripts run one after another

const HOME_NETWORK = "/run/home-network"

def main [iface: string = "", action: string = "", ...rest: string]: nothing -> nothing {
    if $action != "up" { return }
    let home = try { open --raw $HOME_NETWORK | lines } catch { [] }
    if $iface not-in $home { return }
    ^systemctl start --no-block printers-sync.service
}
