#!/usr/bin/env -S nu --no-config-file -I /var/lib/dotfiles/repo/scripts/lib
# decided over every physical link on each event: a link stays locked down until 70-home-network decided it trusted
# (home or a trusted network); only the homelab's share follows home itself

use lib/dispatch.nu [file-lines lab-env lab-nets link-physical ok out untrusted-policy]

const SELF = path self
const HOME_NETWORK = "/run/home-network"
const TRUSTED_NETWORK = "/run/trusted-network"
const MARKER = "/run/persona-lockdown"
const TOR_MARKER = "/run/persona-tor"
const TOR_ROUTER = "/usr/local/bin/tor-router"
# what tor-router routes into; without it fw-egress still holds, open only to pacman's escape
const TOR = "/usr/bin/tor"
const VM_GUEST = "/etc/NetworkManager/vm-guest"
# the install chain's unit: while it exists the chain downloads directly; its last step removes it and reboots
const STAGE_UNIT = "/etc/systemd/system/dotfiles-stage.service"
const VPN_IFACE = "proton0"
const WG_IFACE = "wg0"
# protonvpn-netns' tunnel: its link lives in the namespace, its udp socket in ours with the fwmark
const NETNS = "protonvpn"
const NETNS_IFACE = "wg-protonvpn"
# base/networkmanager's portal_window_s; the fallback is its default
const PORTAL_FILE = "/etc/NetworkManager/portal-seconds"
const PORTAL_S = 300
const PORTAL_UNIT = "persona-portal"
const IFNAME = '^[A-Za-z0-9_.-]{1,15}$'

def policy []: nothing -> string {
    let policy = untrusted-policy
    let policy = if $policy in [firewall-only off] { $policy } else { "lockdown-tor" }
    # tor would carry every download of the install through a few slow exits that some hosts refuse; inbound stays shut
    if $policy == lockdown-tor and ($STAGE_UNIT | path exists) { "firewall-only" } else { $policy }
}

# The links NM has connected (not operstate: a cable without a profile is up, a modem reads unknown).
def connected []: nothing -> table<type: string, state: string, dev: string> {
    # DEVICE last: a bluetooth one is an address, its escaped colons stay in the remainder
    out nmcli -t -f TYPE,STATE,DEVICE device | lines
        | parse --regex '^(?<type>[^:]*):(?<state>[^:]*):(?<dev>.*)$' | where state == connected
}

# Whether any link is not trusted, by NM's state.
def foreign [policy: string]: nothing -> bool {
    if $policy == off { return false }
    let links = connected
    # a modem's or a phone's DEVICE is not its interface; mobile data is never trusted
    if ($links | any { $in.type in [gsm bt] }) { return true }
    let physical = $links | where { link-physical $in.dev } | get dev
    # fail closed
    let trusted = file-lines $TRUSTED_NETWORK
    ($physical | is-empty) or ($physical | any { $in not-in $trusted })
}

def portal-seconds []: nothing -> int {
    file-lines $PORTAL_FILE | get --optional 0 | default "" | if $in =~ '^[1-9]\d*$' { $in | into int } else { $PORTAL_S }
}

def tor-missing []: nothing -> bool {
    not ($TOR | path exists) or not ($TOR_ROUTER | path exists)
}

# Switches to tor; gone names the tunnel going down, whose link may linger until NM deletes it.
def tor-on [policy: string, gone: string = ""]: nothing -> nothing {
    if $policy != lockdown-tor or (tor-missing) or ($VM_GUEST | path exists) { return }
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

# Never over a live proton tunnel: its connmark restore clobbers the wg fwmark. The netns tunnel's mark is read only
# by fw-egress on a foreign link and by tor-router, so portmaster stops beside it there and comes back on a trusted
# link. Kept off on a foreign link under lockdown-tor without tor: its own resolver (root) cannot pass fw-egress,
# while resolved's strict DoT, back once it stops, is the escape route's way to look up pacman's mirrors.
def portmaster-on [policy: string, gone: string = ""]: nothing -> nothing {
    let locked = $policy == lockdown-tor and (foreign $policy)
    let mark_read = $locked or (ok systemctl is-active -q tor-router.service)
    if ($locked and (tor-missing)) or ($mark_read and (ok ip -n $NETNS link show $NETNS_IFACE)) {
        ok systemctl stop portmaster.service | ignore
        return
    }
    if $VPN_IFACE != $gone and (ok ip link show $VPN_IFACE) { return }
    if (ok systemctl is-active -q fw-inbound.service fw-lockdown.service) { ok systemctl start portmaster.service | ignore }
}

# A foreign link's dhcp search domains would route those names to its resolver, ahead of the global ~.
def foreign-dns [iface: string]: nothing -> nothing {
    ok resolvectl domain $iface "" | ignore
    ok resolvectl default-route $iface no | ignore
}

def ipv6-set [dev: string, on: bool]: nothing -> nothing {
    ok sysctl -wq $"net.ipv6.conf.($dev).disable_ipv6=(if $on { 0 } else { 1 })" | ignore
}

def portal-open [iface: string]: nothing -> bool {
    ok systemctl is-active -q $"($PORTAL_UNIT)-($iface).timer"
}

def vpn-event [policy: string, action: string]: nothing -> nothing {
    match $action {
        # as root before the tunnel activates, so toggle-route asks for no portmaster stop of its own
        "pre-up" => { ok systemctl stop portmaster.service | ignore }
        "up" | "vpn-up" => {
            ok systemctl stop portmaster.service | ignore
            tor-off
            # proton's ~. would race resolved's quad9 per query
            foreign-dns $VPN_IFACE
        }
        "down" | "vpn-down" => {
            if (foreign $policy) { tor-on $policy $VPN_IFACE }
            portmaster-on $policy $VPN_IFACE
        }
    }
}

def wg-event [policy: string, action: string]: nothing -> nothing {
    let lab = lab-env
    let metric = $lab.HOMELAB_UNREACHABLE_METRIC? | default ""
    match $action {
        "up" => {
            tor-off
            # the fallback sits above wg-quick's suppress_prefixlength rule and would shadow the tunnel
            for net in (lab-nets $lab) { ok ip route del unreachable $net metric $metric | ignore }
        }
        "down" => {
            if (foreign $policy) { tor-on $policy $WG_IFACE }
            for net in (lab-nets $lab) { ok ip route replace unreachable $net metric $metric | ignore }
        }
    }
    # a running tor route bypasses wg0's own subnet and lans
    ok $TOR_ROUTER home | ignore
}

# Captive portal mode: its pages live on the foreign network, out of reach of tor and strict dot.
def portal [iface: string]: nothing -> nothing {
    if $iface in (file-lines $TRUSTED_NETWORK) or (portal-open $iface) { return }
    let seconds = portal-seconds
    # fw_egress is loaded only under lockdown-tor; strict dot still hides the portal's names without it
    let egress = ok nft list table inet fw_egress
    if $egress and not (ok nft add element inet fw_egress portal $"{ ($iface) timeout ($seconds)s }") {
        print --stderr $"portal: could not open fw_egress for ($iface)"
        exit 1
    }
    let domains = out resolvectl domain $iface | split row ":" | skip 1 | str join ":" | split row --regex '\s+'
        | where $it != ""
    let back = [--quiet --collect $"--unit=($PORTAL_UNIT)-($iface)" $"--on-active=($seconds)s" $SELF $iface portal-end]
    if not (ok systemd-run ...$back ...$domains) {
        if $egress { ok nft delete element inet fw_egress portal $"{ ($iface) }" | ignore }
        print --stderr $"portal: could not schedule its end for ($iface)"
        exit 1
    }
    tor-off
    # portmaster's dns intercept answers from its own dot upstream, never the link's dhcp resolver the portal needs
    ok systemctl stop portmaster.service | ignore
    ok resolvectl dnsovertls $iface no | ignore
    # the global ~. claims every name, so the link's dhcp resolver is asked only with a ~. of its own
    ok resolvectl domain $iface "~." | ignore
}

def portal-end [policy: string, iface: string, domains: list<string>]: nothing -> nothing {
    # gone by its own timeout unless toggle-portal ended the window early
    ok nft delete element inet fw_egress portal $"{ ($iface) }" | ignore
    # the window may have seen the network become trusted: only then are its own domains and resolver wanted back
    let trusted = $policy == off or $iface in (file-lines $TRUSTED_NETWORK)
    if $trusted {
        ok resolvectl domain $iface ...(if ($domains | is-empty) { [""] } else { $domains }) | ignore
    } else {
        foreign-dns $iface
    }
    if (foreign $policy) { tor-on $policy }
    portmaster-on $policy
    let tls = if (ok systemctl is-active -q portmaster.service) { "no" } else if $trusted { "opportunistic" } else { "yes" }
    ok resolvectl dnsovertls $iface $tls | ignore
}

def link-event [policy: string, iface: string, action: string]: nothing -> nothing {
    let uuid = $env.CONNECTION_UUID? | default ""
    if $policy != lockdown-tor {
        ok systemctl stop fw-egress.service | ignore
    } else if not ($VM_GUEST | path exists) {
        ok systemctl start fw-egress.service | ignore
    }
    # off treats every network as trusted; a down decides over the links still up, 70-home-network dropped the gone one
    let foreign = foreign $policy
    if not $foreign {
        if ($MARKER | path exists) {
            rm --force $MARKER
            # the conflict drops lockdown before the load, so a failed load would leave no table at all
            if not (ok systemctl start fw-inbound.service) { ok systemctl start fw-lockdown.service | ignore }
            # a trusted link that came up beside a foreign one got ipv6 off; the foreign one's down lifts it here
            for dev in (connected | get dev | where { link-physical $in }) { ipv6-set $dev true }
        }
        ok systemctl unmask --runtime avahi-daemon.service | ignore
        ok systemctl start avahi-daemon.socket | ignore
        if $action == up {
            ipv6-set $iface true
            ok nmcli connection modify $uuid ipv6.method auto | ignore
            # portmaster's global drop-in is gone whenever it stops (a vpn up, a portal, by hand); pin the link so
            # the strict-dot default never strands lab names on the home resolver, nor a trusted lan's names on its
            # own, neither serving dot on 853
            let tls = if (ok systemctl is-active -q portmaster.service) { "no" } else { "opportunistic" }
            ok resolvectl dnsovertls $iface $tls | ignore
        }
    } else {
        ok systemctl start fw-lockdown.service | ignore
        # mask the daemon, a stop is undone by activation; the unix socket stays enabled for base/systemd
        ok systemctl stop avahi-daemon.socket | ignore
        ok systemctl mask --runtime --now avahi-daemon.service | ignore
        let untrusted = $iface not-in (file-lines $TRUSTED_NETWORK)
        if $action == up and $untrusted { foreign-dns $iface }
        if $action == up and $policy == lockdown-tor {
            ipv6-set $iface false
            if $untrusted { ok nmcli connection modify $uuid ipv6.method disabled | ignore }
        } else if $policy != lockdown-tor {
            ipv6-set $iface true
            if $untrusted { ok nmcli connection modify $uuid ipv6.method auto | ignore }
        }
    }
    # the nas answers only on home's lan or through wg0; a trusted network is neither
    if (file-lines $HOME_NETWORK | is-empty) and not ($"/sys/class/net/($WG_IFACE)" | path exists) {
        ok systemctl stop --no-block mnt-homelab.mount | ignore
    }
    if $foreign { tor-on $policy } else { tor-off }
    portmaster-on $policy
}

# Tor just became usable (installed, tor-router in place): the links' tor decision again, the rest untouched. An open
# portal keeps it off, its end decides.
def tor-arrived [policy: string]: nothing -> nothing {
    let portals = out systemctl list-units --type timer --state active --plain --no-legend $"($PORTAL_UNIT)-*.timer"
    if ($portals | str trim) != "" or not (foreign $policy) { return }
    tor-on $policy
    portmaster-on $policy
}

def main [iface: string = "", action: string = "", ...domains: string]: nothing -> nothing {
    let policy = policy
    if $iface == $VPN_IFACE or $env.VPN_IP_IFACE? == $VPN_IFACE { return (vpn-event $policy $action) }
    if $iface == $WG_IFACE { return (wg-event $policy $action) }
    if $action == portal-end { return (portal-end $policy $iface $domains) }
    if $action == tor-arrived { return (tor-arrived $policy) }
    # toggle-firewall's way back to portmaster, decided here like on every link event
    if $action == portmaster { return (portmaster-on $policy) }
    if $action not-in [up down portal dhcp4-change dhcp6-change] or not ($iface =~ $IFNAME) { return }
    # an unplugged link's node is gone by its down, which under lockdown still re-decides over the links left
    let unplugged = $action == down and ($MARKER | path exists)
    if not (link-physical $iface) and not $unplugged { return }
    if $action in [dhcp4-change dhcp6-change] {
        # NM pushes the link's resolved config again with every lease; an open portal keeps its own
        if $policy != off and $iface not-in (file-lines $TRUSTED_NETWORK) and not (portal-open $iface) { foreign-dns $iface }
        return
    }
    if $action == portal { portal $iface } else { link-event $policy $iface $action }
}
