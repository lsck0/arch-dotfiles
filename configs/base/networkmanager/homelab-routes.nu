#!/usr/bin/nu --no-config-file
# NM dispatcher: on a home link the homelab subnets route out the lan from their own table, ahead of a full-tunnel vpn

const LAB_ENV = "/etc/NetworkManager/homelab.env"
const HOME_NETWORK = "/run/home-network"
const TABLE = "178"
# below wg-quick's suppress_prefixlength 0 rule (32764) and NM wireguard's
const PRIORITY = "30000"
const WG_IFACE = "wg0"
const MIRROR_UPDATE = "/usr/local/bin/mirrorlist-update"
const MIRROR_LINE = "/etc/pacman.d/homelab-mirror"

# a missing binary reads as a failed command, not a crash of the dispatcher
def --wrapped out [...argv: string]: nothing -> string {
    try { do { run-external ...$argv } | complete | get stdout } catch { "" }
}

def --wrapped attempt [...argv: string]: nothing -> nothing {
    let r = try { do { run-external ...$argv } | complete } catch {|e| {exit_code: 1, stderr: $"($e.msg)\n"} }
    if $r.exit_code != 0 { print --stderr --no-newline $r.stderr }
}

def lab-env []: nothing -> record {
    open --raw $LAB_ENV | lines | parse "{key}={value}" | update value { str trim --char '"' }
    | transpose --header-row --as-record
}

# A weekly sort while away drops the homelab mirror; back on a home link or wg0 it goes first again. Queued, not
# waited on: a running sort holds the mirrorlist lock longer than NM's dispatcher timeout.
def mirror-place [line: string]: nothing -> nothing {
    if not ($MIRROR_UPDATE | path exists) or not ($MIRROR_LINE | path exists) { return }
    attempt systemd-run --no-block --quiet --collect $MIRROR_UPDATE homelab $line
}

def mirror-line []: nothing -> string {
    if ($MIRROR_LINE | path exists) { open --raw $MIRROR_LINE | str trim } else { "" }
}

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up dhcp4-change down] or not ($LAB_ENV | path exists) { return }
    let lab = lab-env
    let nets = $lab.HOMELAB_NETS? | default "" | split row " " | where $it != ""
    if ($lab.HOMELAB_DNS? | default "") == "" or ($nets | is-empty) { return }
    let metric = $lab.HOMELAB_UNREACHABLE_METRIC? | default ""

    if $action == down {
        out ip route flush table $TABLE dev $iface | ignore
        if (out ip route show table $TABLE | is-not-empty) { return }
        for net in $nets { out ip rule del to $net lookup $TABLE priority $PRIORITY | ignore }
        return
    }
    if $iface == $WG_IFACE and $action == up { return (mirror-place (mirror-line)) }
    if not ($"/sys/class/net/($iface)/device" | path exists) { return }

    # the persona dispatcher drops these on wg0 up; a stray link event must not re-add them under it
    let wg = $"/sys/class/net/($WG_IFACE)" | path exists
    if not $wg {
        for net in $nets { attempt ip route replace unreachable $net metric $metric }
    }
    let home = if ($HOME_NETWORK | path exists) { open --raw $HOME_NETWORK | lines } else { [] }
    if $iface not-in $home {
        # away with no tunnel the lab mirror only stalls pacman; an empty line drops it until home or wg0 is back
        if ($home | is-empty) and not $wg and $action == up { mirror-place "" }
        return
    }

    # NM re-pushes the link's resolved config on every ip change; the reapply re-enters here, so skip it
    let dns = out nmcli -g IP4.DNS,IP6.DNS device show $iface | lines | where $it != ""
    if $dns != [$lab.HOMELAB_DNS] {
        (
            out nmcli device modify $iface ipv4.dns $lab.HOMELAB_DNS ipv4.dns-search $"~($lab.HOMELAB_DOMAIN? | default '')"
                ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes
        ) | ignore
    }
    # NM's push right behind the reapply's own can still carry the router's yes
    out resolvectl default-route $iface no | ignore

    let gateway = out ip -4 route show default dev $iface | lines | get --optional 0 | default "" | split row " "
        | get --optional 2
    if $gateway == null { return }
    for net in $nets {
        attempt ip route replace $net via $gateway dev $iface table $TABLE
        if (out ip rule list to $net lookup $TABLE | is-empty) {
            attempt ip rule add to $net lookup $TABLE priority $PRIORITY
        }
    }
    mirror-place (mirror-line)
}
