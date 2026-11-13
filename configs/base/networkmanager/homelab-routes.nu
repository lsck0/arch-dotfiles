#!/usr/bin/nu --no-config-file
# NM dispatcher: on a home link the homelab subnets route out the lan from their own table, ahead of a full-tunnel vpn

use lib/dispatch.nu [attempt file-lines lab-env lab-nets link-physical out route-gateway]

const NM_CONF = "/etc/NetworkManager/NetworkManager.conf"
const NM = "org.freedesktop.NetworkManager"
const NM_PATH = "/org/freedesktop/NetworkManager"
const HOME_NETWORK = "/run/home-network"
const TABLE = "178"
# below wg-quick's suppress_prefixlength 0 rule (32764) and NM wireguard's
const PRIORITY = "30000"
const WG_IFACE = "wg0"
const MIRROR_UPDATE = "/usr/local/bin/mirrorlist-update"
const MIRROR_LINE = "/etc/pacman.d/homelab-mirror"

# A weekly sort while away drops the homelab mirror; back on a home link or wg0 it goes first again. Queued, not
# waited on: a running sort holds the mirrorlist lock longer than NM's dispatcher timeout.
def mirror-place [line: string]: nothing -> nothing {
    if not ($MIRROR_UPDATE | path exists) or not ($MIRROR_LINE | path exists) { return }
    attempt systemd-run --no-block --quiet --collect $MIRROR_UPDATE homelab $line
}

def probe-host []: nothing -> string {
    file-lines $NM_CONF | where $it starts-with "uri=" | get --optional 0 | default ""
    | parse --regex '^uri=https?://(?<host>[^/:]+)' | get --optional 0.host | default ""
}

def mirror-line []: nothing -> string {
    if ($MIRROR_LINE | path exists) { open --raw $MIRROR_LINE | str trim } else { "" }
}

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up dhcp4-change down] { return }
    let lab = lab-env
    let nets = lab-nets $lab
    if ($lab.HOMELAB_DNS? | default "") == "" or ($nets | is-empty) { return }
    let metric = $lab.HOMELAB_UNREACHABLE_METRIC? | default ""

    if $action == down {
        out ip route flush table $TABLE dev $iface | ignore
        if (out ip route show table $TABLE | is-not-empty) { return }
        for net in $nets { out ip rule del to $net lookup $TABLE priority $PRIORITY | ignore }
        return
    }
    if $iface == $WG_IFACE and $action == up { return (mirror-place (mirror-line)) }
    if not (link-physical $iface) { return }

    # the persona dispatcher drops these on wg0 up; a stray link event must not re-add them under it
    let wg = $"/sys/class/net/($WG_IFACE)" | path exists
    if not $wg {
        for net in $nets { attempt ip route replace unreachable $net metric $metric }
    }
    let home = file-lines $HOME_NETWORK
    if $iface not-in $home {
        # the dns override below is runtime only (nmcli device modify) and outlives the link's home status, e.g. a
        # network trusted as home and then moved to trusted_gateways: a reapply puts the profile's own dns back
        let dns = out nmcli -g IP4.DNS device show $iface | lines | where $it != ""
        if $dns == [$lab.HOMELAB_DNS] { out nmcli device reapply $iface | ignore }
        # away with no tunnel the lab mirror only stalls pacman; an empty line drops it until home or wg0 is back
        if ($home | is-empty) and not $wg and $action == up { mirror-place "" }
        return
    }

    # NM resolves its connectivity probe on the link
    let domains = [($lab.HOMELAB_DOMAIN? | default '') (probe-host)] | where $it != "" | each { $"~($in)" }
    # NM re-pushes the link's resolved config on every ip change; the reapply re-enters here, so skip it
    let dns = out nmcli -g IP4.DNS,IP6.DNS device show $iface | lines | where $it != ""
    let current = out resolvectl domain $iface | split row ":" | get --optional 1 | default "" | split row " "
        | where $it != ""
    if $dns != [$lab.HOMELAB_DNS] or ($domains | any { $in not-in $current }) {
        (
            out nmcli device modify $iface ipv4.dns $lab.HOMELAB_DNS ipv4.dns-search ($domains | str join ",")
                ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes
        ) | ignore
        # a probe that failed before the domains were in keeps LIMITED until NM's next periodic check
        attempt busctl call --expect-reply=false $NM $NM_PATH $NM CheckConnectivity
    }
    # NM's push right behind the reapply's own can still carry the router's yes
    out resolvectl default-route $iface no | ignore

    let gateway = route-gateway (out ip -4 route show default dev $iface)
    if $gateway == null { return }
    for net in $nets {
        attempt ip route replace $net via $gateway dev $iface table $TABLE
        if (out ip rule list to $net lookup $TABLE | is-empty) {
            attempt ip rule add to $net lookup $TABLE priority $PRIORITY
        }
    }
    mirror-place (mirror-line)
}
