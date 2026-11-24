#!/usr/bin/nu --no-config-file

const TRUSTED_NETWORK = "/run/trusted-network"
# UNKNOWN while NM has not probed yet
const CONNECTED = [FULL UNKNOWN]

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up connectivity-change] { return }
    if $action == connectivity-change and $env.CONNECTIVITY_STATE? not-in $CONNECTED { return }
    # the lookup names our ip to a third party: from a trusted link only (70-home-network)
    let home = if ($TRUSTED_NETWORK | path exists) { open --raw $TRUSTED_NETWORK | lines } else { [] }
    if ($home | is-empty) or ($action == up and $iface not-in $home) { return }
    let users = do { ^loginctl list-users --no-legend } | complete | get stdout | lines
        | each { str trim | split row --regex '\s+' | get --optional 1 } | compact
    for user in $users {
        do { ^systemctl --user -M $"($user)@" start --no-block timezone-auto.service } | complete | ignore
    }
}
