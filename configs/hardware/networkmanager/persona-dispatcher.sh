#!/usr/bin/env bash
# NM dispatcher: lockdown is the resting state (fw-lockdown at boot, again on every down); only an up with every
# physical link home (/run/home-network) lifts it to fw-inbound, mdns and ipv6. a foreign link keeps lockdown, no mdns,
# no ipv6. dhcp never sends the hostname.
iface="${1:-}"
action="${2:-}"

# protonvpn's tunnel came or went outside its toggle (the app, a reconnect, a crash): portmaster follows it as the
# toggle would, off while proton0 is up (it clobbers the wg fwmark), back once it is gone unless the firewall is off
if [ "$iface" = proton0 ] || [ "${VPN_IP_IFACE:-}" = proton0 ]; then
    case "$action" in
    up | vpn-up) systemctl stop portmaster.service 2>/dev/null || true ;;
    down | vpn-down)
        if systemctl is-active -q fw-inbound.service fw-lockdown.service; then
            systemctl start portmaster.service 2>/dev/null || true
        fi
        ;;
    esac
    exit 0
fi
case "$action" in up | down) ;; *) exit 0 ;; esac

HOME_NETWORK=/run/home-network
# fw-lockdown.service sets it on every start: the lockdown is ours, so home lifts it; toggle-firewall.sh clears it
MARKER=/run/persona-lockdown

# physical wifi/ethernet only; a home link that vanished (usb unplug) still counts on its down
[ -e "/sys/class/net/${iface}/device" ] || nft get element inet fw home_ifaces "{ $iface }" >/dev/null 2>&1 || exit 0

# the effects are global, so trust is decided over every physical link, not just this one
home=0
if [ "$action" = up ] && [ -e "$HOME_NETWORK" ]; then
    home=1
    for n in /sys/class/net/*; do
        [ -e "$n/device" ] && [ "$(cat "$n/operstate")" = up ] || continue
        grep -qx "${n##*/}" "$HOME_NETWORK" || home=0
    done
fi

if ((home)); then
    if rm "$MARKER" 2>/dev/null; then
        # the conflict drops lockdown before the load, so a failed load would leave no table at all
        systemctl start fw-inbound.service 2>/dev/null || systemctl start fw-lockdown.service 2>/dev/null
    fi
    # a start fills home_ifaces itself; an fw-inbound already running learns this link here
    nft add element inet fw home_ifaces "{ $iface }" 2>/dev/null
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
fi
# tor-router's lan bypass follows the home links home-network.sh just decided; a no-op while tor-router is off
[ -x /usr/local/bin/tor-router ] && /usr/local/bin/tor-router home 2>/dev/null || true
# the app firewall rides with the firewall toggle, but never over a live protonvpn tunnel (it clobbers the wg fwmark)
if systemctl is-active -q fw-inbound.service fw-lockdown.service && ! ip link show proton0 >/dev/null 2>&1; then
    systemctl start portmaster.service 2>/dev/null || true
fi
