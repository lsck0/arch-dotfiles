#!/usr/bin/nu --no-config-file
# NM dispatcher: on a home link the homelab subnets route out the lan from their own table, ahead of a full-tunnel vpn

const LAB_ENV = "/etc/NetworkManager/homelab.env"
const HOME_NETWORK = "/run/home-network"
const TABLE = "178"
# below wg-quick's suppress_prefixlength 0 rule (32764) and NM wireguard's
const PRIORITY = "30000"
# behind wg0's routes; off home the homelab fails fast instead of leaking out the default route
const UNREACHABLE_METRIC = "4000"

def --wrapped out [...argv: string]: nothing -> string {
    do { run-external ...$argv } | complete | get stdout
}

def --wrapped attempt [...argv: string]: nothing -> nothing {
    let r = do { run-external ...$argv } | complete
    if $r.exit_code != 0 { print --stderr --no-newline $r.stderr }
}

def lab-env []: nothing -> record {
    open --raw $LAB_ENV | lines | parse "{key}={value}" | update value { str trim --char '"' }
    | transpose --header-row --as-record
}

def main [iface: string = "", action: string = ""]: nothing -> nothing {
    if $action not-in [up dhcp4-change down] or not ($LAB_ENV | path exists) { return }
    let lab = lab-env
    let nets = $lab.HOMELAB_NETS? | default "" | split row " " | where $it != ""
    if ($lab.HOMELAB_DNS? | default "") == "" or ($nets | is-empty) { return }
    if not ($"/sys/class/net/($iface)/device" | path exists) { return }

    if $action == down {
        out ip route flush table $TABLE dev $iface | ignore
        if (out ip route show table $TABLE | is-not-empty) { return }
        for net in $nets { out ip rule del to $net lookup $TABLE priority $PRIORITY | ignore }
        return
    }

    # the persona dispatcher drops these on wg0 up; a stray link event must not re-add them under it
    if not ("/sys/class/net/wg0" | path exists) {
        for net in $nets { attempt ip route replace unreachable $net metric $UNREACHABLE_METRIC }
    }
    if not ($HOME_NETWORK | path exists) or $iface not-in (open --raw $HOME_NETWORK | lines) { return }

    # through NM, which re-pushes the link's resolved config on every ip change; the reapply re-enters here, so skip
    let dns = out nmcli -g IP4.DNS,IP6.DNS device show $iface | lines | where $it != ""
    if $dns != [$lab.HOMELAB_DNS] {
        (
            out nmcli device modify $iface ipv4.dns $lab.HOMELAB_DNS ipv4.dns-search $"~($lab.HOMELAB_DOMAIN? | default '')"
                ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes
        ) | ignore
    }
    # NM's push right behind the reapply's own can still carry the router's yes; it never computes yes again
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
}
