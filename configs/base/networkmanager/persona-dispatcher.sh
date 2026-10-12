#!/usr/bin/env bash
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
iface="${1:-}"
action="${2:-}"

HOME_NETWORK=/run/home-network
# fw-lockdown.service sets it on every start: the lockdown is ours, so home lifts it; toggle-firewall.sh clears it
MARKER=/run/persona-lockdown
# set while tor-router runs because of this script, so a tor the user started is never stopped here
TOR_MARKER=/run/persona-tor
TOR_ROUTER=/usr/local/bin/tor-router
# networkmanager/system.sh on a vm: the host's fw_egress already holds the guest, so no egress kill switch and no tor
VM_GUEST=/etc/NetworkManager/vm-guest
VPN_IFACE=proton0
WG_IFACE=wg0
PORTAL_S=120
PORTAL_UNIT=persona-portal

# a physical link NM has connected is not on the home list. NM's state, not operstate: a cable without a profile is
# up but carries nothing, a modem's link reads unknown while it carries everything
foreign() {
    local type state dev
    # DEVICE last: a bluetooth one is an address, its escaped colons stay in the remainder
    while IFS=: read -r type state dev; do
        [ "$state" = connected ] || continue
        # a modem's or a phone's DEVICE is not its network interface; mobile data is never home anyway
        case "$type" in gsm | bt) return 0 ;; esac
        [ -e "/sys/class/net/$dev/device" ] || continue
        grep -qx "$dev" "$HOME_NETWORK" 2>/dev/null || return 0
    done < <(nmcli -t -f TYPE,STATE,DEVICE device 2>/dev/null)
    return 1
}

# tor_on [gone]: never while a tunnel carries everything; gone names the one going down, its link may linger until NM
# deletes it
tor_on() {
    local t
    [ -x "$TOR_ROUTER" ] && [ ! -e "$VM_GUEST" ] || return 0
    for t in "$VPN_IFACE" "$WG_IFACE"; do
        [ "$t" = "${1:-}" ] || ! ip link show "$t" >/dev/null 2>&1 || return 0
    done
    systemctl is-active -q tor-router.service && return 0
    touch "$TOR_MARKER"
    # tor takes seconds to start, the dispatcher must not wait on it; fw-egress drops what it cannot carry yet
    systemctl start --no-block tor-router.service
}

tor_off() {
    rm "$TOR_MARKER" 2>/dev/null || return 0
    systemctl stop --no-block tor-router.service
}

# the app firewall rides with the firewall toggle, but never over a live protonvpn tunnel (it clobbers the wg fwmark)
portmaster_on() {
    if systemctl is-active -q fw-inbound.service fw-lockdown.service && ! ip link show "$VPN_IFACE" >/dev/null 2>&1; then
        systemctl start portmaster.service 2>/dev/null || true
    fi
}

# protonvpn's tunnel came or went, from auto-vpn, the toggle, the app, a reconnect or a crash. portmaster follows it
# as the toggle would: off while proton0 is up (it clobbers the wg fwmark), back once it is gone unless the firewall is
# off
if [ "$iface" = "$VPN_IFACE" ] || [ "${VPN_IP_IFACE:-}" = "$VPN_IFACE" ]; then
    case "$action" in
    up | vpn-up)
        systemctl stop portmaster.service 2>/dev/null || true
        tor_off
        # one dns upstream: resolved's quad9 over tls, now through the tunnel; proton's ~. would race it per query
        resolvectl domain "$VPN_IFACE" "" 2>/dev/null || true
        resolvectl default-route "$VPN_IFACE" no 2>/dev/null || true
        ;;
    down | vpn-down)
        foreign && tor_on "$VPN_IFACE"
        if systemctl is-active -q fw-inbound.service fw-lockdown.service; then
            systemctl start portmaster.service 2>/dev/null || true
        fi
        ;;
    esac
    exit 0
fi

# the homelab tunnel is full (AllowedIPs 0.0.0.0/0): tor hands over to it as to protonvpn, else its dns and traffic
# would go through tor. portmaster and resolved stay as they are
if [ "$iface" = "$WG_IFACE" ]; then
    case "$action" in
    up) tor_off ;;
    down) foreign && tor_on "$WG_IFACE" ;;
    esac
    exit 0
fi

# after the window the portal set has already closed the link (nft timeout); this only brings tor, dns and portmaster
# back. the rest of the arguments are the link's own domains from before the window; none clears with "", a bare
# resolvectl domain <iface> only prints
if [ "$action" = portal-end ]; then
    [ $# -gt 2 ] || set -- "$@" ""
    resolvectl domain "$iface" "${@:3}" 2>/dev/null || true
    foreign && tor_on
    portmaster_on
    # the link follows the global setting: plain while portmaster runs (portmaster/dotfiles.conf), else opportunistic
    if systemctl is-active -q portmaster.service; then
        resolvectl dnsovertls "$iface" no 2>/dev/null || true
    else
        resolvectl dnsovertls "$iface" opportunistic 2>/dev/null || true
    fi
    exit 0
fi

case "$action" in up | down | portal) ;; *) exit 0 ;; esac
[[ "$iface" =~ ^[A-Za-z0-9_.-]{1,15}$ ]] || exit 0
# physical wifi/ethernet only; 70-home-network already dropped a vanished link from every home list
[ -e "/sys/class/net/${iface}/device" ] || exit 0

if [ "$action" = portal ]; then
    # a captive portal's pages live on the foreign network itself: tor would carry them away, strict dns over tls
    # cannot reach its resolver. one window at a time
    grep -qx "$iface" "$HOME_NETWORK" 2>/dev/null && exit 0
    nft get element inet fw_egress portal "{ $iface }" >/dev/null 2>&1 && exit 0
    nft add element inet fw_egress portal "{ $iface timeout ${PORTAL_S}s }" || exit 1
    # "Link 3 (wlan0): a.example ~b.example", ifnames carry no colon
    domains=$(resolvectl domain "$iface" 2>/dev/null) || domains=:
    read -ra domains <<<"${domains#*:}"
    if ! systemd-run --quiet --collect --unit="$PORTAL_UNIT" --on-active="${PORTAL_S}s" \
        "$(readlink -f "$0")" "$iface" portal-end "${domains[@]}"; then
        # without the way back the window stays shut
        nft delete element inet fw_egress portal "{ $iface }" 2>/dev/null
        exit 1
    fi
    tor_off
    # portmaster's dns intercept resolves over dot to 853, which the portal set does not pass
    systemctl stop portmaster.service 2>/dev/null || true
    resolvectl dnsovertls "$iface" no 2>/dev/null || true
    # the global ~. claims every name, so the link's dhcp resolver is asked only with a ~. of its own
    resolvectl domain "$iface" "~." 2>/dev/null || true
    exit 0
fi

# the egress rules are the kill switch: always on, a stop by hand lasts until the next network event
[ -e "$VM_GUEST" ] || systemctl start fw-egress.service 2>/dev/null || true

# the effects are global, so trust is decided over every physical link, not just this one
if [ "$action" = up ] && [ -e "$HOME_NETWORK" ] && ! foreign; then
    if rm "$MARKER" 2>/dev/null; then
        # the conflict drops lockdown before the load, so a failed load would leave no table at all
        systemctl start fw-inbound.service 2>/dev/null || systemctl start fw-lockdown.service 2>/dev/null
    fi
    systemctl unmask --runtime avahi-daemon.socket avahi-daemon.service 2>/dev/null || true
    systemctl start avahi-daemon.socket 2>/dev/null || true
    sysctl -wq "net.ipv6.conf.${iface}.disable_ipv6=0" 2>/dev/null || true
    # undo a disable from a home connect that was not recognised in time
    nmcli connection modify "$CONNECTION_UUID" ipv6.method auto 2>/dev/null || true
else
    # a no-op on a running lockdown, so one the user chose keeps no marker and survives home
    systemctl start fw-lockdown.service 2>/dev/null || true
    # a stop alone is undone by dbus activation through the dbus-org.freedesktop.Avahi alias
    systemctl mask --runtime --now avahi-daemon.socket avahi-daemon.service 2>/dev/null || true
    if [ "$action" = up ]; then
        sysctl -wq "net.ipv6.conf.${iface}.disable_ipv6=1" 2>/dev/null || true
        # the next connect to this foreign profile starts without ipv6; system.sh sets home profiles back to auto
        grep -qx "$iface" "$HOME_NETWORK" 2>/dev/null ||
            nmcli connection modify "$CONNECTION_UUID" ipv6.method disabled 2>/dev/null || true
    fi
    # the homelab share (configs/core/nas) never stays mounted to whatever answers its address off home
    if [ ! -s "$HOME_NETWORK" ] && [ ! -e /sys/class/net/wg0 ]; then
        systemctl stop --no-block mnt-homelab.mount 2>/dev/null || true
    fi
fi
if foreign; then tor_on; else tor_off; fi
portmaster_on
