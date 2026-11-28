#!/usr/bin/env -S nu --no-config-file -I /var/lib/dotfiles/repo/scripts/lib
# fail safe: without a gateway no default and no rule, so game packets stay on the vpn

# Resolved against the lib path, the root copy's scripts/lib here and the checkout's when the engine loads mod.nu, so
# it holds in both; base/networkmanager's own dispatchers use their /etc copy beside them.
use ../../configs/base/networkmanager/scripts/lib/dispatch.nu [attempt lab-env lab-nets link-physical out]

# the skb mark games-bypass.nft sets and fw-egress' game_mark lets out; kept in sync with both
const GAME_MARK = "0x6761"
const TABLE = "100"
# above homelab (30000) and a full-tunnel vpn's own rules, below the kernel's local (0)
const PRIORITY = "9000"
const FAMILIES = ["-4" "-6"]
const HOMELAB_TABLE = "178"
# games-bypass.nft's tunnel; its split default routes look connected
const VPN_IFACE = "proton0"

def routes [family: string, table: string]: nothing -> list<record> {
    let listed = out ip -j $family route show table $table | str trim
    if $listed == "" { [] } else { $listed | from json }
}

# Dev and gateway too: main holds fe80::/64 once per link at one metric, which a replace or add collapses to one.
def route-key [r: record]: nothing -> string {
    $"($r.type? | default unicast) ($r.dst) ($r.gateway? | default -) ($r.dev? | default -) ($r.metric? | default 0)"
}

def route-args [r: record]: nothing -> list<string> {
    [($r.type? | default unicast) $r.dst]
    | append (if $r.gateway? != null { [via $r.gateway] } else { [] })
    | append (if $r.dev? != null { [dev $r.dev] } else { [] })
    | append (if $r.metric? != null { [metric ($r.metric | into string)] } else { [] })
}

# Nmcli has the link's own gateway even under proton0; -g escapes ipv6 colons.
def gateway [iface: string, family: string]: nothing -> string {
    let field = if $family == "-4" { "IP4.GATEWAY" } else { "IP6.GATEWAY" }
    let listed = out nmcli -g $field device show $iface | lines | get --optional 0 | default "" | str replace --all '\' ''
    if $listed != "" or $family == "-6" { return $listed }
    out ip -4 route show default dev $iface | lines | get --optional 0 | default "" | split row " " | get --optional 2
    | default ""
}

# One default route per family in the table, so the link that came up last owns it; false without a gateway.
def family-up [iface: string, family: string]: nothing -> bool {
    let via = gateway $iface $family
    if $via == "" { return false }
    attempt ip $family route replace default via $via dev $iface table $TABLE
    if not (out ip $family rule list priority $PRIORITY | str contains $"fwmark ($GAME_MARK)") {
        attempt ip $family rule add fwmark $GAME_MARK lookup $TABLE priority $PRIORITY
    }
    true
}

def route-up [iface: string]: nothing -> nothing {
    for family in $FAMILIES { family-up $iface $family | ignore }
}

def default-missing [family: string]: nothing -> bool {
    routes $family $TABLE | where $it.dst == "default" | is-empty
}

# Mirrors everything but the default into the table: main's connected routes, table 178, the lab's unreachables.
def routes-sync [family: string]: nothing -> nothing {
    let connected = routes $family main
        | where $it.dst != "default" and $it.type? == null and $it.gateway? == null
        | where $it.dev? not-in [null $VPN_IFACE]
    let lab = lab-env
    let metric = $lab.HOMELAB_UNREACHABLE_METRIC? | default ""
    let unreachable = lab-nets $lab | where { ($in | str contains ":") == ($family == "-6") }
        | each {|net| {type: unreachable dst: $net metric: $metric} }
    let wanted = $connected | append (routes $family $HOMELAB_TABLE) | append $unreachable
    let keys = $wanted | each { route-key $in }
    let present = routes $family $TABLE | where $it.dst != "default"
    for r in ($present | where (route-key $it) not-in $keys) {
        attempt ip $family route del ...(route-args $r) table $TABLE
    }
    let have = $present | each { route-key $in }
    for r in ($wanted | where (route-key $it) not-in $have) {
        attempt ip $family route append ...(route-args $r) table $TABLE
    }
}

# The connected ethernet and wifi links with a device node, the ones whose gateway the table may point at.
export def links-physical []: nothing -> list<string> {
    out nmcli -t -f DEVICE,TYPE,STATE device | lines | split column ":" dev type state
    | where state == connected and type in [ethernet wifi] and (link-physical $it.dev)
    | get dev
}

def defaults-empty []: nothing -> bool {
    $FAMILIES | all {|f| default-missing $f }
}

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up dhcp4-change dhcp6-change down connectivity-change] { return }

    # virbr0, docker bridges and tunnels only change the mirrored routes; an unplugged link's node is gone by its down
    let physical = link-physical $iface
    if $action == down {
        if $physical {
            for family in $FAMILIES { out ip $family route flush table $TABLE dev $iface | ignore }
        }
    } else if $physical {
        route-up $iface
    }
    # A family without a default takes the first physical link that has its gateway now: another link after a down,
    # or the link itself once its RA default arrived after its up, which no dispatcher event of its own reports.
    # A family that has one keeps its owner.
    let missing = $FAMILIES | where {|f| default-missing $f }
    if ($missing | is-not-empty) {
        let links = links-physical | where {|l| $action != down or $l != $iface }
        for family in $missing {
            for link in $links { if (family-up $link $family) { break } }
        }
    }

    if (defaults-empty) {
        for family in $FAMILIES {
            out ip $family rule del fwmark $GAME_MARK lookup $TABLE priority $PRIORITY | ignore
            out ip $family route flush table $TABLE | ignore
        }
        return
    }
    for family in $FAMILIES { routes-sync $family }
}
