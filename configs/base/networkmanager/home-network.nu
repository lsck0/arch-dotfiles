#!/usr/bin/nu --no-config-file
# NM dispatcher: a link is trusted by the hardware mac plus a known gateway mac, never the ssid, which a foreign network
# can copy. Home (home-gateways: the homelab's network) is trusted too; a trusted network (trusted-gateways) only lifts
# the lockdown. /run/trusted-network feeds the firewall sets and tor-router; /run/home-network the homelab wiring.

const GATEWAYS = "/etc/NetworkManager/home-gateways"
const TRUSTED_GATEWAYS = "/etc/NetworkManager/trusted-gateways"
const HOME_NETWORK = "/run/home-network"
const TRUSTED_NETWORK = "/run/trusted-network"
const TOR_ROUTER = "/usr/local/bin/tor-router"
const TABLES = [fw_egress fw portmaster_bypass]
const NO_MAC = "00:00:00:00:00:00"
# /sys/class/net/<link>/addr_assign_type of a mac the device itself carries
const ASSIGN_PERMANENT = "0"

# a missing binary reads as a failed command, not a crash of the dispatcher
def --wrapped out [...argv: string]: nothing -> string {
    try { do { run-external ...$argv } | complete | get stdout } catch { "" }
}

def physical [link: string]: nothing -> bool {
    $"/sys/class/net/($link)/device" | path exists
}

def links-in [file: path]: nothing -> list<string> {
    if ($file | path exists) { open --raw $file | lines } else { [] }
}

def macs [file: path]: nothing -> list<string> {
    if ($file | path exists) { open --raw $file | lines | where $it != "" | str lowercase } else { [] }
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

def link-gateway-in [link: string, gateways: list<string>]: nothing -> bool {
    let address = try { open --raw $"/sys/class/net/($link)/address" } catch { "" }
    let assign_type = try { open --raw $"/sys/class/net/($link)/addr_assign_type" } catch { "" }
    if not (hardware-mac-in-use $address (out ethtool -P $link) $assign_type) { return false }
    let gateway = out ip -4 route show default dev $link | lines | get --optional 0 | default "" | split row " "
        | get --optional 2
    if $gateway == null { return false }
    let mac = gateway-mac $link $gateway | str lowercase
    $mac != "" and $mac in $gateways
}

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up down] { return }
    if not (physical $iface) and $iface not-in (links-in $TRUSTED_NETWORK) { return }
    let home_gateways = macs $GATEWAYS
    let any_gateways = $home_gateways ++ (macs $TRUSTED_GATEWAYS) | uniq
    let trusted = if ($any_gateways | is-empty) { [] } else {
        glob /sys/class/net/* | path basename
        | where {|link| (physical $link) and not ($action == down and $link == $iface) and (link-gateway-in $link $any_gateways) }
    }
    let home = $trusted | where {|link| link-gateway-in $link $home_gateways }
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
