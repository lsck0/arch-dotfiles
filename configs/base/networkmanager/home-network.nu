#!/usr/bin/nu --no-config-file
# NM dispatcher: a link is trusted by the hardware mac plus a known gateway, never the ssid, which a foreign network
# can copy. Home (home-gateways: the homelab's network) is trusted too; a trusted network (trusted-gateways) only lifts
# the lockdown. /run/trusted-network feeds the firewall sets and tor-router; /run/home-network the homelab wiring.
# A home-gateways line is `<mac> <gateway address> <dhcp server identifier>`: a router mac cannot be rotated once
# known, so home also wants the address it answers on and the dhcp server its lease names. A mac alone is only
# trusted, and not even that once a full line names the same mac.

const GATEWAYS = "/etc/NetworkManager/home-gateways"
const TRUSTED_GATEWAYS = "/etc/NetworkManager/trusted-gateways"
const HOME_NETWORK = "/run/home-network"
const TRUSTED_NETWORK = "/run/trusted-network"
const TOR_ROUTER = "/usr/local/bin/tor-router"
const TABLES = [fw_egress fw portmaster_bypass]
const NO_MAC = "00:00:00:00:00:00"
export const TIER_HOME = "home"
export const TIER_TRUSTED = "trusted"
export const TIER_NONE = "untrusted"
# /sys/class/net/<link>/addr_assign_type of a mac the device itself carries
const ASSIGN_PERMANENT = "0"

# a missing binary reads as a failed command, not a crash of the dispatcher
def --wrapped out [...argv: string]: nothing -> string {
    try { do { run-external ...$argv } | complete | get stdout } catch { "" }
}

def physical [link: string]: nothing -> bool {
    $"/sys/class/net/($link)/device" | path exists
}

def file-read [file: path]: nothing -> string {
    if ($file | path exists) { open --raw $file } else { "" }
}

# home-gateways' lines; a malformed one is skipped, a mac alone has no gateway and no dhcp_server.
export def gateways-parse [text: string]: nothing -> table<mac: string, gateway: any, dhcp_server: any> {
    $text | lines | str trim | where $it != "" and not ($it | str starts-with "#") | each {|l|
        let f = $l | str lowercase | split row --regex '\s+'
        match ($f | length) {
            1 => {mac: $f.0, gateway: null, dhcp_server: null}
            3 => {mac: $f.0, gateway: $f.1, dhcp_server: $f.2}
            _ => null
        }
    } | compact
}

# `ip -4 route show default dev <link>`'s gateway.
export def route-gateway [route: string]: nothing -> any {
    $route | lines | get --optional 0 | default "" | parse --regex '^default via (?<gw>\S+)' | get --optional 0.gw
}

# `nmcli -t -f DHCP4.OPTION device show <link>`'s server identifier, null without a lease.
export def dhcp-server [options: string]: nothing -> any {
    $options | parse --regex '(?m):dhcp_server_identifier = (?<id>\S+)$' | get --optional 0.id
}

# The tier a link reaches by what it sees ({mac gateway dhcp_server} of its default route): home only when a home line
# names all three; trusted by a trusted mac, or a home mac no full line names.
export def link-tier [home: table, trusted: list<string>, seen: any]: nothing -> string {
    if $seen == null or ($seen.mac | is-empty) { return $TIER_NONE }
    let named = $home | where mac == $seen.mac
    let full = $named | where gateway != null
    if ($full | any {|l| $l.gateway == $seen.gateway and $l.dhcp_server == $seen.dhcp_server }) { return $TIER_HOME }
    if $seen.mac in $trusted or (($full | is-empty) and ($named | is-not-empty)) { return $TIER_TRUSTED }
    $TIER_NONE
}

# Writes the links one per line, atomically; none removes the file.
def links-save [file: path, links: list<string>]: nothing -> nothing {
    if ($links | is-empty) { rm --force $file; return }
    let next = $"($file).new"
    $links | each { $"($in)\n" } | str join | save --force $next
    ^chmod 644 $next
    mv --force $next $file
}

def gateway-mac [link: string, gateway: string]: nothing -> string {
    let known = out ip neigh show $gateway dev $link | parse --regex 'lladdr (?<mac>\S+)' | get --optional 0.mac
    if $known != null { return $known }
    # fw-egress drops a ping out of an undecided link, arp sits below it
    out arping -c1 -w1 -I $link $gateway | parse --regex '(?m)^\w* reply from \S+ \[(?<mac>[0-9A-Fa-f:]+)\]'
    | get --optional 0.mac | default ""
}

# NM puts a random mac on every foreign network; only home profiles keep the hardware one. Compared with the hardware's
# own (ethtool -P): addr_assign_type stays 3 once NM's scan mac was set back. A nic with no stored permanent mac
# (virtio, some usb adapters) answers all-zero; it is home only while the kernel says the mac is the device's own
# (addr_assign_type 0), which a random-mac adapter or tether (1) never says.
export def hardware-mac-in-use [address: string, ethtool: string, assign_type: string]: nothing -> bool {
    let hardware = $ethtool | parse --regex 'Permanent address: (?<mac>\S+)' | get --optional 0.mac | default ""
        | str lowercase
    let address = $address | str trim | str lowercase
    if $address in ["" $NO_MAC] { return false }
    if $hardware in ["" $NO_MAC] { return (($assign_type | str trim) == $ASSIGN_PERMANENT) }
    $address == $hardware
}

# What a link sees of its default route, null unless it carries the hardware mac and has a gateway.
def link-observe [link: string]: nothing -> any {
    let address = try { open --raw $"/sys/class/net/($link)/address" } catch { "" }
    let assign_type = try { open --raw $"/sys/class/net/($link)/addr_assign_type" } catch { "" }
    if not (hardware-mac-in-use $address (out ethtool -P $link) $assign_type) { return null }
    let gateway = route-gateway (out ip -4 route show default dev $link)
    if $gateway == null { return null }
    let mac = gateway-mac $link $gateway | str lowercase
    {mac: $mac, gateway: $gateway, dhcp_server: (dhcp-server (out nmcli -t -f DHCP4.OPTION device show $link))}
}

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up down] { return }
    if not (physical $iface) and $iface not-in (file-read $TRUSTED_NETWORK | lines) { return }
    let home_gateways = gateways-parse (file-read $GATEWAYS)
    let trusted_gateways = file-read $TRUSTED_GATEWAYS | lines | where $it != "" | str lowercase
    let tiers = if ($home_gateways | is-empty) and ($trusted_gateways | is-empty) { [] } else {
        glob /sys/class/net/* | path basename
        | where {|link| (physical $link) and not ($action == down and $link == $iface) }
        | each {|link| {link: $link, tier: (link-tier $home_gateways $trusted_gateways (link-observe $link))} }
    }
    let trusted = $tiers | where tier != $TIER_NONE | get link
    let home = $tiers | where tier == $TIER_HOME | get link
    links-save $HOME_NETWORK $home
    links-save $TRUSTED_NETWORK $trusted
    # one transaction per table so a trusted link never drops out in between
    for table in $TABLES {
        if (out nft list set inet $table trusted_links) == "" { continue }
        let add = if ($trusted | is-empty) { "" } else { $"add element inet ($table) trusted_links { ($trusted | str join ',') }\n" }
        $"flush set inet ($table) trusted_links\n($add)" | do { ^nft -f - } | complete | ignore
    }
    if ($TOR_ROUTER | path exists) { do { ^$TOR_ROUTER home } | complete | ignore }
}
