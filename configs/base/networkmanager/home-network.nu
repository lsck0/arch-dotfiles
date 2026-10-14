#!/usr/bin/nu --no-config-file
# NM dispatcher, first of the three: the one home rule. a physical link is home while it is on its hardware mac and its
# default gateway's mac is in home-gateways; /run/home-network lists those links one per line and is gone without one.
# never the ssid: a foreign network can copy that, but only a home profile keeps the hardware mac (mod.nu), and only
# with the home wifi's key does it associate at all

const GATEWAYS = "/etc/NetworkManager/home-gateways"
const HOME_NETWORK = "/run/home-network"
const TOR_ROUTER = "/usr/local/bin/tor-router"
# the egress kill switch, fw-inbound's lan services and portmaster's lab-dns bypass all key on the home links
const TABLES = [fw_egress fw portmaster_bypass]

def --wrapped out [...argv: string]: nothing -> string {
    do { run-external ...$argv } | complete | get stdout
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
    # right after a connect the gateway is often unresolved, and fw-egress drops a ping out of a link not yet decided;
    # arp sits below it, so ask the gateway directly
    out arping -c1 -w1 -I $link $gateway | parse --regex '(?m)^\w* reply from \S+ \[(?<mac>[0-9A-Fa-f:]+)\]'
    | get --optional 0.mac | default ""
}

def link-is-home [link: string, gateways: list<string>]: nothing -> bool {
    # NM puts a random mac on every foreign network; only home profiles keep the hardware one
    let permanent = out ethtool -P $link | str trim | split row " " | last
    if $permanent == "" or (open --raw $"/sys/class/net/($link)/address" | str trim) != $permanent { return false }
    let gateway = out ip -4 route show default dev $link | lines | get --optional 0 | default "" | split row " "
        | get --optional 2
    if $gateway == null { return false }
    let mac = gateway-mac $link $gateway | str lowercase
    $mac != "" and $mac in $gateways
}

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up down] { return }
    # a home link that vanished (usb unplug) still counts on its down
    if not (physical $iface) and $iface not-in (home-links) { return }
    # no gateways file (guest, locked secrets) leaves every link foreign
    let gateways = if ($GATEWAYS | path exists) { open --raw $GATEWAYS | lines | str lowercase } else { [] }
    let home = if ($gateways | is-empty) { [] } else {
        glob /sys/class/net/* | path basename
        | where {|link| (physical $link) and not ($action == down and $link == $iface) and (link-is-home $link $gateways) }
    }
    if ($home | is-empty) {
        rm --force $HOME_NETWORK
    } else {
        # readers poll it, so swap it in whole
        let next = $"($HOME_NETWORK).new"
        $home | each { $"($in)\n" } | str join | save --force $next
        ^chmod 644 $next
        mv --force $next $HOME_NETWORK
    }
    # one transaction per table, so a home link never drops out and a link that left home never keeps its place
    for table in $TABLES {
        if (do { ^nft list set inet $table home_ifaces } | complete).exit_code != 0 { continue }
        let add = if ($home | is-empty) { "" } else { $"add element inet ($table) home_ifaces { ($home | str join ',') }\n" }
        $"flush set inet ($table) home_ifaces\n($add)" | do { ^nft -f - } | complete | ignore
    }
    # tor-router's lan bypass too; a no-op while it is off
    if ($TOR_ROUTER | path exists) { do { ^$TOR_ROUTER home } | complete | ignore }
}
