#!/usr/bin/nu --no-config-file
# NM dispatcher: home is the hardware mac plus a known gateway mac, never the ssid, which a foreign network can copy

const GATEWAYS = "/etc/NetworkManager/home-gateways"
const HOME_NETWORK = "/run/home-network"
const TOR_ROUTER = "/usr/local/bin/tor-router"
const TABLES = [fw_egress fw portmaster_bypass]
# NET_ADDR_PERM in addr_assign_type: the address came from the hardware
const ADDR_PERMANENT = "0"

# a missing binary reads as a failed command, not a crash of the dispatcher
def --wrapped out [...argv: string]: nothing -> string {
    try { do { run-external ...$argv } | complete | get stdout } catch { "" }
}

def physical [link: string]: nothing -> bool {
    $"/sys/class/net/($link)/device" | path exists
}

def home-links []: nothing -> list<string> {
    if ($HOME_NETWORK | path exists) { open --raw $HOME_NETWORK | lines } else { [] }
}

def gateway-mac [link: string, gateway: string]: nothing -> string {
    let known = out ip neigh show $gateway dev $link | parse --regex 'lladdr (?<mac>\S+)' | get --optional 0.mac
    if $known != null { return $known }
    # fw-egress drops a ping out of an undecided link, arp sits below it
    out arping -c1 -w1 -I $link $gateway | parse --regex '(?m)^\w* reply from \S+ \[(?<mac>[0-9A-Fa-f:]+)\]'
    | get --optional 0.mac | default ""
}

def link-is-home [link: string, gateways: list<string>]: nothing -> bool {
    # NM puts a random mac on every foreign network; only home profiles keep the hardware one
    # permaddr shows only when the current mac is not the hardware one, and never when the hardware one is all zeros
    let info = try { out ip -j -d link show $link | from json | get 0 } catch { null }
    if $info == null or $info.permaddr? != null or ($info.address? | default "") == "" { return false }
    # so the kernel's own word too: a random-mac usb adapter or tether reads 1, a mac set over a zero one 3
    let assign = try { open --raw $"/sys/class/net/($link)/addr_assign_type" | str trim } catch { "" }
    if $assign != $ADDR_PERMANENT { return false }
    let gateway = out ip -4 route show default dev $link | lines | get --optional 0 | default "" | split row " "
        | get --optional 2
    if $gateway == null { return false }
    let mac = gateway-mac $link $gateway | str lowercase
    $mac != "" and $mac in $gateways
}

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up down] { return }
    if not (physical $iface) and $iface not-in (home-links) { return }
    let gateways = if ($GATEWAYS | path exists) { open --raw $GATEWAYS | lines | str lowercase } else { [] }
    let home = if ($gateways | is-empty) { [] } else {
        glob /sys/class/net/* | path basename
        | where {|link| (physical $link) and not ($action == down and $link == $iface) and (link-is-home $link $gateways) }
    }
    if ($home | is-empty) {
        rm --force $HOME_NETWORK
    } else {
        let next = $"($HOME_NETWORK).new"
        $home | each { $"($in)\n" } | str join | save --force $next
        ^chmod 644 $next
        mv --force $next $HOME_NETWORK
    }
    # one transaction per table so a home link never drops out in between
    for table in $TABLES {
        if (out nft list set inet $table home_ifaces) == "" { continue }
        let add = if ($home | is-empty) { "" } else { $"add element inet ($table) home_ifaces { ($home | str join ',') }\n" }
        $"flush set inet ($table) home_ifaces\n($add)" | do { ^nft -f - } | complete | ignore
    }
    if ($TOR_ROUTER | path exists) { do { ^$TOR_ROUTER home } | complete | ignore }
}
