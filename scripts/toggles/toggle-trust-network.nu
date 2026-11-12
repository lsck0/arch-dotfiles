#!/usr/bin/env -S nu --no-config-file
# The default route's gateway mac joins the trusted list: no lockdown there, but none of home's homelab wiring (home
# is home_gateways and the secrets' list). Unlocked, the list is configs/secrets/keys/trusted-gateways (the repo is
# public, and a mac is all a rogue access point needs), else the trusted_gateways option; the system apply that
# follows re-decides the link.

use lib.nu [notify switch-run trusted-links]
use ../lib/secrets.nu [secret-is-plaintext OWNER_WITNESS]
use ../lib/state.nu [EXIT_PENDING]

const DOT = path self ../dot.nu
const SECRET = path self ../../configs/secrets/keys/trusted-gateways
const WITNESS = path self ../.. | path join $OWNER_WITNESS
const OPTION = "base/networkmanager.trusted_gateways"

# The physical link of the default route and its gateway's mac, null without one.
def uplink []: nothing -> any {
    let route = ^ip -j -4 route show default | from json
        | where {|r| $r.gateway? != null and ($"/sys/class/net/($r.dev)/device" | path exists) }
        | sort-by {|r| $r.metric? | default 0 } | get --optional 0
    if $route == null { return null }
    let mac = ^ip -j neigh show $route.gateway dev $route.dev | from json | get --optional 0.lladdr
    if $mac == null { return null }
    {dev: $route.dev, mac: ($mac | str lowercase)}
}

def option-listed []: nothing -> list<string> {
    ^nu --no-config-file $DOT set $OPTION --json | from json | get modules.0.options | where key == trusted_gateways
    | get 0.value | str lowercase
}

# Locked, the file is git-crypt's blob: nothing readable.
def secret-listed []: nothing -> list<string> {
    if not (secret-is-plaintext $SECRET) { return [] }
    open --raw $SECRET | lines | where $it =~ '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$' | str lowercase
}

def unlocked []: nothing -> bool { secret-is-plaintext $WITNESS }

def listed []: nothing -> list<string> { (secret-listed) ++ (option-listed) | uniq }

# A pending system part is no failure: the option is written, the network follows on the next system apply.
def settled [run: record]: nothing -> nothing {
    if $run.exit_code == $EXIT_PENDING {
        notify "Trusted network" "Saved; the network changes with the next dot apply --system"
    } else if $run.exit_code != 0 {
        error make {msg: ($run.stderr | str trim | lines | last 1 | str join "")}
    }
}

# Unlocked, the secret takes the whole list and the option is emptied of what it held; locked, the option does.
def store [gateways: list<string>]: nothing -> nothing {
    if not (unlocked) {
        settled (^nu --no-config-file $DOT set --machine $OPTION ($gateways | to nuon) | complete)
        return
    }
    # emptied, never deleted: root keeps its last copy of a secret it is not sent, as for a locked one; renamed into
    # place, so a concurrent system apply packs the old list or the new one, never half of it
    $gateways | each { $"($in)\n" } | str join | save --force $"($SECRET).new"
    mv --force $"($SECRET).new" $SECRET
    if (option-listed | is-not-empty) {
        settled (^nu --no-config-file $DOT set --machine $OPTION "[]" | complete)
    } else {
        settled (^nu --no-config-file $DOT apply --system | complete)
    }
}

def link []: nothing -> record {
    let link = uplink
    if $link == null { error make {msg: "no wired or wifi link with a gateway"} }
    $link
}

def main [action: string = "toggle", --json] {
    switch-run {
        label: "Trusted network"
        is-on: {|| let link = uplink; $link != null and $link.dev in (trusted-links) }
        on: {||
            # a rejoined wifi has a random mac: storing a listed one again reruns the home step
            store (listed | append (link).mac | uniq)
        }
        off: {||
            let gateways = listed
            let mac = (link).mac
            if $mac not-in $gateways {
                error make {msg: (if (unlocked) {
                    "home by home_gateways or configs/secrets/keys/home-gateways, not a trusted network"
                } else {
                    "configs/secrets is locked: unlock it to change the trusted list"
                })}
            }
            store ($gateways | where $it != $mac)
        }
        # only while a link has a gateway
        available: {|| uplink | is-not-empty }
    } $action --json=$json
}
