#!/usr/bin/nu --no-config-file
# NM dispatcher, the untrusted-network persona. the state is decided over every physical link on each event:
#
#   boot, any down   LOCKDOWN  fw-lockdown (nothing new gets in) and fw-egress (configs/base/nftables/fw-egress.nft: a
#                              link not on the home list carries only dhcp, ndp, wireguard handshakes and tor). the
#                              resting state, so a link is closed from its first packet until 70-home-network decided
#   up, all home     HOME      fw-inbound, avahi, ipv6; a tor-router started here stops. home is the hardware mac plus
#                              a known gateway mac (70-home-network), never the ssid
#   up, any foreign  FOREIGN   lockdown, no avahi, no ipv6 on the link, tor-router carries everything at once, before
#                              any login; auto-vpn (configs/base/protonvpn, after login) connects protonvpn through it
#   proton0 up       VPN       the tor-router started here stops; fw-egress leaves proton0 the only way out
#   proton0 down     FOREIGN   again while any link is foreign: tor until protonvpn reconnects, never the bare link
#   wg0 up           VPN       the same for the homelab full tunnel; toggle-root wg calls this, NM may not dispatch it
#   wg0 down         FOREIGN   again while any link is foreign
#   portal <iface>   PORTAL    by hand only, never on an event (as root: <this script> <iface> portal): dns, http and
#                              https straight out that foreign link for PORTAL_S, tor paused, then FOREIGN again
#
# dhcp never sends the hostname (NetworkManager.conf), resolved has no llmnr or mdns, avahi runs only at home.
#
# untrusted-policy (mod.nu's untrusted_policy) scales it down: firewall-only keeps the lockdown and the avahi mask off
# home but no egress kill switch, tor or ipv6 off; off treats every network as home. missing or unknown is lockdown-tor

const SELF = path self
const HOME_NETWORK = "/run/home-network"
# fw-lockdown.service sets it on every start: the lockdown is ours, so home lifts it; toggle-firewall.nu clears it
const MARKER = "/run/persona-lockdown"
# set while tor-router runs because of this script, so a tor the user started is never stopped here
const TOR_MARKER = "/run/persona-tor"
const TOR_ROUTER = "/usr/local/bin/tor-router"
# mod.nu on a vm: the host's fw_egress already holds the guest, so no egress kill switch and no tor
const VM_GUEST = "/etc/NetworkManager/vm-guest"
const POLICY_FILE = "/etc/NetworkManager/untrusted-policy"
const HOMELAB_ENV = "/etc/NetworkManager/homelab.env"
const VPN_IFACE = "proton0"
const WG_IFACE = "wg0"
const PORTAL_S = 120
const PORTAL_UNIT = "persona-portal"
# homelab-routes' fail-fast fallback
const UNREACHABLE_METRIC = "4000"
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

# a physical link NM has connected is not on the home list. NM's state, not operstate: a cable without a profile is
# up but carries nothing, a modem's link reads unknown while it carries everything
def foreign [policy: string]: nothing -> bool {
    if $policy == off { return false }
    # DEVICE last: a bluetooth one is an address, its escaped colons stay in the remainder
    let links = out nmcli -t -f TYPE,STATE,DEVICE device | lines
        | parse --regex '^(?<type>[^:]*):(?<state>[^:]*):(?<dev>.*)$' | where state == connected
    # a modem's or a phone's DEVICE is not its network interface; mobile data is never home anyway
    if ($links | any { $in.type in [gsm bt] }) { return true }
    let physical = $links | where { $"/sys/class/net/($in.dev)/device" | path exists } | get dev
    # fail closed: home only when a physical link is confirmed on the home list
    let home = home-links
    ($physical | is-empty) or ($physical | any { $in not-in $home })
}

# never while a tunnel carries everything; gone names the one going down, its link may linger until NM deletes it
def tor-on [policy: string, gone: string = ""]: nothing -> nothing {
    if $policy != lockdown-tor or not ($TOR_ROUTER | path exists) or ($VM_GUEST | path exists) { return }
    if ([$VPN_IFACE $WG_IFACE] | any {|t| $t != $gone and (ok ip link show $t) }) { return }
    if (ok systemctl is-active -q tor-router.service) { return }
    touch $TOR_MARKER
    # tor takes seconds to start, the dispatcher must not wait on it; fw-egress drops what it cannot carry yet
    ok systemctl start --no-block tor-router.service | ignore
}

def tor-off []: nothing -> nothing {
    if not ($TOR_MARKER | path exists) { return }
    rm --force $TOR_MARKER
    ok systemctl stop --no-block tor-router.service | ignore
}

# the app firewall rides with the firewall toggle, but never over a live protonvpn tunnel (it clobbers the wg fwmark)
def portmaster-on []: nothing -> nothing {
    if (ok systemctl is-active -q fw-inbound.service fw-lockdown.service) and not (ok ip link show $VPN_IFACE) {
        ok systemctl start portmaster.service | ignore
    }
}

# protonvpn's tunnel came or went, from auto-vpn, the toggle, the app, a reconnect or a crash
def vpn-event [policy: string, action: string]: nothing -> nothing {
    match $action {
        "up" | "vpn-up" => {
            ok systemctl stop portmaster.service | ignore
            tor-off
            # one dns upstream: resolved's quad9 over tls, now through the tunnel; proton's ~. would race it per query
            ok resolvectl domain $VPN_IFACE "" | ignore
            ok resolvectl default-route $VPN_IFACE no | ignore
        }
        "down" | "vpn-down" => {
            if (foreign $policy) { tor-on $policy $VPN_IFACE }
            if (ok systemctl is-active -q fw-inbound.service fw-lockdown.service) {
                ok systemctl start portmaster.service | ignore
            }
        }
    }
}

# the homelab tunnel is full (AllowedIPs 0.0.0.0/0): tor hands over to it as to protonvpn
def wg-event [policy: string, action: string]: nothing -> nothing {
    match $action {
        "up" => {
            tor-off
            # off home the unreachable fallback sits above wg-quick's suppress_prefixlength 0 rule and would shadow the
            # full tunnel
            for net in (lab-nets) { ok ip route del unreachable $net metric $UNREACHABLE_METRIC | ignore }
        }
        "down" => {
            if (foreign $policy) { tor-on $policy $WG_IFACE }
            for net in (lab-nets) { ok ip route replace unreachable $net metric $UNREACHABLE_METRIC | ignore }
        }
    }
}

# a captive portal's pages live on the foreign network itself: tor would carry them away, strict dns over tls cannot
# reach its resolver. one window at a time
def portal [iface: string]: nothing -> nothing {
    if $iface in (home-links) or (ok nft get element inet fw_egress portal $"{ ($iface) }") { return }
    if not (ok nft add element inet fw_egress portal $"{ ($iface) timeout ($PORTAL_S)s }") { exit 1 }
    # "Link 3 (wlan0): a.example ~b.example", ifnames carry no colon
    let domains = out resolvectl domain $iface | split row ":" | skip 1 | str join ":" | split row --regex '\s+'
        | where $it != ""
    let back = [--quiet --collect $"--unit=($PORTAL_UNIT)" $"--on-active=($PORTAL_S)s" $SELF $iface portal-end]
    if not (ok systemd-run ...$back ...$domains) {
        # without the way back the window stays shut
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

# after the window the portal set has already closed the link (nft timeout); this brings tor, dns and portmaster back.
# domains are the link's own from before the window; none clears with ""
def portal-end [policy: string, iface: string, domains: list<string>]: nothing -> nothing {
    ok resolvectl domain $iface ...(if ($domains | is-empty) { [""] } else { $domains }) | ignore
    if (foreign $policy) { tor-on $policy }
    portmaster-on
    # the link follows the global setting: plain while portmaster runs (portmaster/dotfiles.conf), else opportunistic
    let tls = if (ok systemctl is-active -q portmaster.service) { "no" } else { "opportunistic" }
    ok resolvectl dnsovertls $iface $tls | ignore
}

def link-event [policy: string, iface: string, action: string]: nothing -> nothing {
    let uuid = $env.CONNECTION_UUID? | default ""
    # the egress rules are the kill switch: always on, a stop by hand lasts until the next network event
    if $policy != lockdown-tor {
        ok systemctl stop fw-egress.service | ignore
    } else if not ($VM_GUEST | path exists) {
        ok systemctl start fw-egress.service | ignore
    }
    # the effects are global, so trust is decided over every physical link, not just this one
    if $action == up and ($HOME_NETWORK | path exists) and not (foreign $policy) {
        if ($MARKER | path exists) {
            rm --force $MARKER
            # the conflict drops lockdown before the load, so a failed load would leave no table at all
            if not (ok systemctl start fw-inbound.service) { ok systemctl start fw-lockdown.service | ignore }
        }
        ok systemctl unmask --runtime avahi-daemon.socket avahi-daemon.service | ignore
        ok systemctl start avahi-daemon.socket | ignore
        ok sysctl -wq $"net.ipv6.conf.($iface).disable_ipv6=0" | ignore
        # undo a disable from a home connect that was not recognised in time
        ok nmcli connection modify $uuid ipv6.method auto | ignore
    } else {
        # a no-op on a running lockdown, so one the user chose keeps no marker and survives home
        ok systemctl start fw-lockdown.service | ignore
        # a stop alone is undone by dbus activation through the dbus-org.freedesktop.Avahi alias
        ok systemctl mask --runtime --now avahi-daemon.socket avahi-daemon.service | ignore
        if $action == up and $policy == lockdown-tor {
            ok sysctl -wq $"net.ipv6.conf.($iface).disable_ipv6=1" | ignore
            # the next connect to this foreign profile starts without ipv6; mod.nu sets home profiles back to auto
            if $iface not-in (home-links) { ok nmcli connection modify $uuid ipv6.method disabled | ignore }
        }
        # the homelab share (configs/core/nas) never stays mounted to whatever answers its address off home
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
    # physical wifi/ethernet only; 70-home-network already dropped a vanished link from every home list
    if not ($"/sys/class/net/($iface)/device" | path exists) { return }
    if $action == portal { portal $iface } else { link-event $policy $iface $action }
}
