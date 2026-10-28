#!/usr/bin/nu --no-config-file
# decided over every physical link on each event: a link stays locked down until 70-home-network decided it

const SELF = path self
const HOME_NETWORK = "/run/home-network"
const MARKER = "/run/persona-lockdown"
const TOR_MARKER = "/run/persona-tor"
const TOR_ROUTER = "/usr/local/bin/tor-router"
const VM_GUEST = "/etc/NetworkManager/vm-guest"
const POLICY_FILE = "/etc/NetworkManager/untrusted-policy"
const HOMELAB_ENV = "/etc/NetworkManager/homelab.env"
const VPN_IFACE = "proton0"
const WG_IFACE = "wg0"
# protonvpn-netns' tunnel: its link lives in the namespace, its udp socket in ours with the fwmark
const NETNS = "protonvpn"
const NETNS_IFACE = "wg-protonvpn"
const PORTAL_S = 120
const PORTAL_UNIT = "persona-portal"
const UNREACHABLE_METRIC = "4000"  # kept in sync by hand with homelab-routes.nu's own copy; same ordering invariant
const IFNAME = '^[A-Za-z0-9_.-]{1,15}$'

def --wrapped out [...argv: string]: nothing -> string {
    do { run-external ...$argv } | complete | get stdout
}

def --wrapped ok [...argv: string]: nothing -> bool {
    (do { run-external ...$argv } | complete).exit_code == 0
}

def home-links []: nothing -> list<string> {
    if ($HOME_NETWORK | path exists) { open --raw $HOME_NETWORK | lines } else { [] }
}

def policy []: nothing -> string {
    let policy = if ($POLICY_FILE | path exists) { open --raw $POLICY_FILE | str trim } else { "" }
    if $policy in [firewall-only off] { $policy } else { "lockdown-tor" }
}

def lab-nets []: nothing -> list<string> {
    if not ($HOMELAB_ENV | path exists) { return [] }
    open --raw $HOMELAB_ENV | lines | parse "{key}={value}" | where key == HOMELAB_NETS | get --optional 0.value
    | default "" | str trim --char '"' | split row " " | where $it != ""
}

# Whether any link is not home, by NM's state (not operstate: a cable without a profile is up, a modem reads unknown).
def foreign [policy: string]: nothing -> bool {
    if $policy == off { return false }
    # DEVICE last: a bluetooth one is an address, its escaped colons stay in the remainder
    let links = out nmcli -t -f TYPE,STATE,DEVICE device | lines
        | parse --regex '^(?<type>[^:]*):(?<state>[^:]*):(?<dev>.*)$' | where state == connected
    # a modem's or a phone's DEVICE is not its interface; mobile data is never home
    if ($links | any { $in.type in [gsm bt] }) { return true }
    let physical = $links | where { $"/sys/class/net/($in.dev)/device" | path exists } | get dev
    # fail closed
    let home = home-links
    ($physical | is-empty) or ($physical | any { $in not-in $home })
}

# Switches to tor; gone names the tunnel going down, whose link may linger until NM deletes it.
def tor-on [policy: string, gone: string = ""]: nothing -> nothing {
    if $policy != lockdown-tor or not ($TOR_ROUTER | path exists) or ($VM_GUEST | path exists) { return }
    if ([$VPN_IFACE $WG_IFACE] | any {|t| $t != $gone and (ok ip link show $t) }) { return }
    if (ok systemctl is-active -q tor-router.service) { return }
    touch $TOR_MARKER
    ok systemctl start --no-block tor-router.service | ignore
}

def tor-off []: nothing -> nothing {
    if not ($TOR_MARKER | path exists) { return }
    rm --force $TOR_MARKER
    ok systemctl stop --no-block tor-router.service | ignore
}

# Never over a live proton tunnel: its connmark restore clobbers the wg fwmark.
def portmaster-on [gone: string = ""]: nothing -> nothing {
    if ($VPN_IFACE != $gone and (ok ip link show $VPN_IFACE)) or (ok ip -n $NETNS link show $NETNS_IFACE) { return }
    if (ok systemctl is-active -q fw-inbound.service fw-lockdown.service) { ok systemctl start portmaster.service | ignore }
}

def vpn-event [policy: string, action: string]: nothing -> nothing {
    match $action {
        "up" | "vpn-up" => {
            ok systemctl stop portmaster.service | ignore
            tor-off
            # proton's ~. would race resolved's quad9 per query
            ok resolvectl domain $VPN_IFACE "" | ignore
            ok resolvectl default-route $VPN_IFACE no | ignore
        }
        "down" | "vpn-down" => {
            if (foreign $policy) { tor-on $policy $VPN_IFACE }
            portmaster-on $VPN_IFACE
        }
    }
}

def wg-event [policy: string, action: string]: nothing -> nothing {
    match $action {
        "up" => {
            tor-off
            # the fallback sits above wg-quick's suppress_prefixlength rule and would shadow the tunnel
            for net in (lab-nets) { ok ip route del unreachable $net metric $UNREACHABLE_METRIC | ignore }
        }
        "down" => {
            if (foreign $policy) { tor-on $policy $WG_IFACE }
            for net in (lab-nets) { ok ip route replace unreachable $net metric $UNREACHABLE_METRIC | ignore }
        }
    }
}

# Captive portal mode: its pages live on the foreign network, out of reach of tor and strict dot.
def portal [iface: string]: nothing -> nothing {
    if $iface in (home-links) or (ok nft get element inet fw_egress portal $"{ ($iface) }") { return }
    if not (ok nft add element inet fw_egress portal $"{ ($iface) timeout ($PORTAL_S)s }") { exit 1 }
    let domains = out resolvectl domain $iface | split row ":" | skip 1 | str join ":" | split row --regex '\s+'
        | where $it != ""
    let back = [--quiet --collect $"--unit=($PORTAL_UNIT)" $"--on-active=($PORTAL_S)s" $SELF $iface portal-end]
    if not (ok systemd-run ...$back ...$domains) {
        ok nft delete element inet fw_egress portal $"{ ($iface) }" | ignore
        exit 1
    }
    tor-off
    # portmaster's dns intercept resolves over dot to 853, which the portal set does not pass
    ok systemctl stop portmaster.service | ignore
    ok resolvectl dnsovertls $iface no | ignore
    # the global ~. claims every name, so the link's dhcp resolver is asked only with a ~. of its own
    ok resolvectl domain $iface "~." | ignore
}

def portal-end [policy: string, iface: string, domains: list<string>]: nothing -> nothing {
    ok resolvectl domain $iface ...(if ($domains | is-empty) { [""] } else { $domains }) | ignore
    if (foreign $policy) { tor-on $policy }
    portmaster-on
    let tls = if (ok systemctl is-active -q portmaster.service) { "no" } else { "opportunistic" }
    ok resolvectl dnsovertls $iface $tls | ignore
}

def link-event [policy: string, iface: string, action: string]: nothing -> nothing {
    let uuid = $env.CONNECTION_UUID? | default ""
    if $policy != lockdown-tor {
        ok systemctl stop fw-egress.service | ignore
    } else if not ($VM_GUEST | path exists) {
        ok systemctl start fw-egress.service | ignore
    }
    # off treats every network as home, a known gateway or not
    if $policy == off or ($action == up and ($HOME_NETWORK | path exists) and not (foreign $policy)) {
        if ($MARKER | path exists) {
            rm --force $MARKER
            # the conflict drops lockdown before the load, so a failed load would leave no table at all
            if not (ok systemctl start fw-inbound.service) { ok systemctl start fw-lockdown.service | ignore }
        }
        ok systemctl unmask --runtime avahi-daemon.service | ignore
        ok systemctl start avahi-daemon.socket | ignore
        ok sysctl -wq $"net.ipv6.conf.($iface).disable_ipv6=0" | ignore
        ok nmcli connection modify $uuid ipv6.method auto | ignore
        # portmaster's global drop-in is gone whenever it stops (a vpn up, a portal, by hand); pin the link so the
        # strict-dot default never strands lab names on the home resolver, which serves no dot on 853
        let tls = if (ok systemctl is-active -q portmaster.service) { "no" } else { "opportunistic" }
        ok resolvectl dnsovertls $iface $tls | ignore
    } else {
        ok systemctl start fw-lockdown.service | ignore
        # mask the daemon, a stop is undone by activation; the unix socket stays enabled for base/systemd
        ok systemctl stop avahi-daemon.socket | ignore
        ok systemctl mask --runtime --now avahi-daemon.service | ignore
        if $action == up and $policy == lockdown-tor {
            ok sysctl -wq $"net.ipv6.conf.($iface).disable_ipv6=1" | ignore
            if $iface not-in (home-links) { ok nmcli connection modify $uuid ipv6.method disabled | ignore }
        } else if $policy != lockdown-tor {
            ok sysctl -wq $"net.ipv6.conf.($iface).disable_ipv6=0" | ignore
            if $iface not-in (home-links) { ok nmcli connection modify $uuid ipv6.method auto | ignore }
        }
        if (home-links | is-empty) and not ($"/sys/class/net/($WG_IFACE)" | path exists) {
            ok systemctl stop --no-block mnt-homelab.mount | ignore
        }
    }
    if (foreign $policy) { tor-on $policy } else { tor-off }
    portmaster-on
}

def main [iface: string = "", action: string = "", ...domains: string]: nothing -> nothing {
    let policy = policy
    if $iface == $VPN_IFACE or $env.VPN_IP_IFACE? == $VPN_IFACE { return (vpn-event $policy $action) }
    if $iface == $WG_IFACE { return (wg-event $policy $action) }
    if $action == portal-end { return (portal-end $policy $iface $domains) }
    if $action not-in [up down portal] or not ($iface =~ $IFNAME) { return }
    if not ($"/sys/class/net/($iface)/device" | path exists) { return }
    if $action == portal { portal $iface } else { link-event $policy $iface $action }
}
