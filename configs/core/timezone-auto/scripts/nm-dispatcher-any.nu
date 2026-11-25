#!/usr/bin/nu --no-config-file
# NM dispatcher in nm-dispatcher.nu's place under core/timezone-auto's any_network: every connected link starts the
# lookup, not only a trusted one

# UNKNOWN while NM has not probed yet, or never does (base/networkmanager's connectivity_check off)
const CONNECTED = [FULL UNKNOWN]

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up connectivity-change] { return }
    if $action == connectivity-change and $env.CONNECTIVITY_STATE? not-in $CONNECTED { return }
    let users = do { ^loginctl list-users --no-legend } | complete | get stdout | lines
        | each { str trim | split row --regex '\s+' | get --optional 1 } | compact
    for user in $users {
        do { ^systemctl --user -M $"($user)@" start --no-block timezone-auto.service } | complete | ignore
    }
}
