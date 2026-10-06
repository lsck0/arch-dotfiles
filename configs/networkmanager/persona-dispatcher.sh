#!/usr/bin/env bash
# NM dispatcher: an untrusted network (a spoofed mac is in use) gets a fresh random idspoof netident persona
# on every connect; home (the hardware mac, our permanent policy) restores it. the mac itself is NM's random.
# shares the idspoof owner marker with anonymous-socks, and stands down while the socks pool owns the persona.
iface="${1:-}"
action="${2:-}"
[ "$action" = up ] || exit 0

# physical wifi/ethernet only
case "$iface" in lo | docker* | veth* | virbr* | wg* | br-* | waydroid* | tun* | tap* | lxc*) exit 0 ;; esac
[ -e "/sys/class/net/${iface}/address" ] || exit 0
command -v idspoof >/dev/null 2>&1 || exit 0

# the logged-in user's runtime dir holds the shared idspoof owner marker
rt=""
for d in /run/user/*; do
    u=${d##*/}
    [ "$u" -ge 1000 ] 2>/dev/null && {
        rt=$d
        break
    }
done
owner="${rt:+${rt}/idspoof-owner}"

# the anonymous-socks pool projects its own persona; never clobber its circuits
[ -n "$owner" ] && [ -r "$owner" ] && [ "$(cat "$owner")" = socks ] && exit 0

cur=$(cat "/sys/class/net/${iface}/address")
perm=$(ethtool -P "$iface" 2>/dev/null | awk '{print $NF}')

idspoof restore --netident -q 2>/dev/null || true
[ -n "$owner" ] && rm -f "$owner"
if [ -z "$perm" ] || [ "$cur" != "$perm" ]; then
    # untrusted: fresh random persona, restrictive firewall, no mdns hostname broadcast, no ipv6 to bypass the tunnel
    personas=(windows macos ios linux android)
    idspoof apply --netident --persona "${personas[RANDOM % ${#personas[@]}]}" -q 2>/dev/null || true
    [ -n "$owner" ] && echo persona >"$owner"
    systemctl start fw-lockdown.service 2>/dev/null || true
    systemctl stop avahi-daemon.socket avahi-daemon.service 2>/dev/null || true
    sysctl -wq "net.ipv6.conf.${iface}.disable_ipv6=1" 2>/dev/null || true
else
    # home: default firewall, mdns and ipv6 back for local discovery
    systemctl start fw-inbound.service 2>/dev/null || true
    systemctl start avahi-daemon.socket 2>/dev/null || true
    sysctl -wq "net.ipv6.conf.${iface}.disable_ipv6=0" 2>/dev/null || true
fi
# the app firewall rides with both, but never over a live protonvpn tunnel (it clobbers the wg fwmark)
ip link show proton0 >/dev/null 2>&1 || systemctl start portmaster.service 2>/dev/null || true
