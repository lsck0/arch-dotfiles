#!/usr/bin/nu --no-config-file

const HOME_NETWORK = "/run/home-network"
# UNKNOWN when the connectivity check is off (75-connectivity-check, at home)
const CONNECTED = [FULL UNKNOWN]

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up connectivity-change] { return }
    if $action == connectivity-change and $env.CONNECTIVITY_STATE? not-in $CONNECTED { return }
    # the lookup names our ip to a third party: from a home link only (70-home-network), never an untrusted one
    let home = if ($HOME_NETWORK | path exists) { open --raw $HOME_NETWORK | lines } else { [] }
    if ($home | is-empty) or ($action == up and $iface not-in $home) { return }
    let users = do { ^loginctl list-users --no-legend } | complete | get stdout | lines
        | each { str trim | split row --regex '\s+' | get --optional 1 } | compact
    for user in $users {
        do { ^systemctl --user -M $"($user)@" start --no-block timezone-auto.service } | complete | ignore
    }
}
