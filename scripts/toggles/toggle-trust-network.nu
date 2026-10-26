#!/usr/bin/env -S nu --no-config-file
# The default route's gateway mac joins home_gateways; dot set's system apply re-decides the link.

use lib.nu [notify switch-run]

const DOT = path self ../dot.nu
const OPTION = "base/networkmanager.home_gateways"
const HOME_NETWORK = "/run/home-network"
const EXIT_SYSTEM_PENDING = 3

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

def home-links []: nothing -> list<string> {
    if ($HOME_NETWORK | path exists) { open --raw $HOME_NETWORK | lines } else { [] }
}

def listed []: nothing -> list<string> {
    ^nu --no-config-file $DOT set $OPTION --json | from json | get modules.0.options | where key == home_gateways
    | get 0.value | str lowercase
}

# A pending system part is no failure: the option is written, the network follows on the next system apply.
def settled [run: record]: nothing -> nothing {
    if $run.exit_code == $EXIT_SYSTEM_PENDING {
        notify "Trusted network" "Saved; the network changes with the next dot apply --system"
    } else if $run.exit_code != 0 {
        error make {msg: ($run.stderr | str trim | lines | last 1 | str join "")}
    }
}

def store [gateways: list<string>]: nothing -> nothing {
    settled (^nu --no-config-file $DOT set --machine $OPTION ($gateways | to nuon) | complete)
}

# A rejoined wifi has a random mac: storing the list again reruns the home step.
def reconverge [gateways: list<string>]: nothing -> nothing { store $gateways }

def link []: nothing -> record {
    let link = uplink
    if $link == null { error make {msg: "no wired or wifi link with a gateway"} }
    $link
}

def main [action: string = "toggle", --json] {
    switch-run {
        label: "Trusted network"
        is-on: {|| let link = uplink; $link != null and $link.dev in (home-links) }
        on: {||
            let gateways = listed
            let mac = (link).mac
            if $mac not-in $gateways { store ($gateways | append $mac) } else { reconverge $gateways }
        }
        off: {||
            let gateways = listed
            let mac = (link).mac
            if $mac not-in $gateways {
                error make {msg: "trusted by configs/secrets/keys/home-gateways, not the option"}
            }
            store ($gateways | where $it != $mac)
        }
        # only while a link has a gateway
        available: {|| uplink | is-not-empty }
    } $action --json=$json
}

