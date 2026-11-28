#!/usr/bin/nu --no-config-file

const TRUSTED_NETWORK = "/run/trusted-network"
# core/timezone-auto's any_network: present, every connected link starts the lookup, not only a trusted one
const ANY_NETWORK = "/etc/NetworkManager/timezone-auto-any-network"
# UNKNOWN while NM has not probed yet, or never does (base/networkmanager's connectivity_check off)
const CONNECTED = [FULL UNKNOWN]
# a user logging out has a manager on its way down: nothing to start there
const USER_STATES_STARTABLE = [active online lingering]
# systemctl's exit when the unit does not exist: a user without core/timezone-auto (a service account), expected
const EXIT_UNIT_NOT_FOUND = 5

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up connectivity-change] { return }
    if $action == connectivity-change and $env.CONNECTIVITY_STATE? not-in $CONNECTED { return }
    # the lookup names our ip to a third party: from a trusted link only (70-home-network)
    let home = if ($TRUSTED_NETWORK | path exists) { open --raw $TRUSTED_NETWORK | lines } else { [] }
    let trusted = ($home | is-not-empty) and ($action != up or $iface in $home)
    if not $trusted and not ($ANY_NETWORK | path exists) { return }
    let listed = ^loginctl list-users --no-legend | complete
    if $listed.exit_code != 0 {
        print -e $"timezone-auto: loginctl list-users: ($listed.stderr | str trim)"
        exit 1
    }
    let users = $listed.stdout | lines | each { str trim | split row --regex '\s+' }
        | where { ($in | length) >= 4 and ($in | last) in $USER_STATES_STARTABLE } | each { get 1 }
    let failed = $users | each {|user|
        let start = ^systemctl --user -M $"($user)@" start --no-block timezone-auto.service | complete
        if $start.exit_code not-in [0 $EXIT_UNIT_NOT_FOUND] {
            print -e $"timezone-auto: starting it for ($user): ($start.stderr | str trim)"
            $user
        }
    }
    # nm-dispatcher logs a script's nonzero exit as a warning: the visible trace of a failed start
    if ($failed | is-not-empty) { exit 1 }
}
