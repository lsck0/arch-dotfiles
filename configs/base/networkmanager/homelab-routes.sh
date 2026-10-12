#!/usr/bin/env bash
# NM dispatcher: on a home link (/run/home-network) the homelab subnets route straight out the lan from their own
# table, looked up ahead of a full-tunnel vpn's rules (wg-quick, NM wireguard); wg0's main-table routes stay untouched,
# so they hold again once home is left; virbr0 nat follows. on a HOMELAB machine an unreachable fallback catches the rest
iface="${1:-}"
action="${2:-}"
case "$action" in up | dhcp4-change | down) ;; *) exit 0 ;; esac

HOMELAB_NETS="10.100.0.0/16 10.200.0.0/16"
# split-horizon dns: at home *.lsck0.dev resolves via the lab router, which answers the lan edge address (10.200.0.200:
# the full-speed mirror, searxng, ...) instead of the public cloudflare one. the home lan, so homelab-routes' own table
# is not involved; tor and portmaster let its :53 past out a home link (tor/tor-router, portmaster/portmaster-bypass.nft)
LAB_DNS=192.168.178.29
LAB_DOMAIN=lsck0.dev
TABLE=178
# below wg-quick's suppress_prefixlength 0 rule (32764) and NM wireguard's
PRIORITY=30000
# behind wg0's main-table routes; off home and wg0 the homelab fails fast instead of leaking out the default route
UNREACHABLE_METRIC=4000
HOME_NETWORK=/run/home-network
HOMELAB_MARKER=/etc/NetworkManager/homelab

# physical wifi/ethernet only
[ -e "/sys/class/net/${iface}/device" ] || exit 0

if [ "$action" = down ]; then
    # drop the split-horizon route with the homelab routes: off this link the name resolves via the global path again
    resolvectl revert "$iface" 2>/dev/null || true
    ip route flush table "$TABLE" dev "$iface" 2>/dev/null
    ip route show table "$TABLE" 2>/dev/null | grep -q . && exit 0
    for net in $HOMELAB_NETS; do
        ip rule del to "$net" lookup "$TABLE" priority "$PRIORITY" 2>/dev/null
    done
    exit 0
fi

if [ -e "$HOMELAB_MARKER" ]; then
    for net in $HOMELAB_NETS; do
        ip route replace unreachable "$net" metric "$UNREACHABLE_METRIC"
    done
fi

grep -qx "$iface" "$HOME_NETWORK" 2>/dev/null || exit 0

# lsck0.dev only, this link only: the lab router serves the whole zone split-horizon, everything else keeps the global
# route (resolved quad9 / portmaster cloudflare). default-route off so nothing but lsck0.dev ever reaches the lab router.
# re-run on every up/dhcp4-change, so a lease renewal that re-pushes the link's dhcp dns cannot drop it
resolvectl dns "$iface" "$LAB_DNS" 2>/dev/null || true
resolvectl domain "$iface" "~${LAB_DOMAIN}" 2>/dev/null || true
resolvectl default-route "$iface" no 2>/dev/null || true

gw=$(ip -4 route show default dev "$iface" | awk '{print $3; exit}')
[ -n "$gw" ] || exit 0
for net in $HOMELAB_NETS; do
    ip route replace "$net" via "$gw" dev "$iface" table "$TABLE"
    ip rule list to "$net" lookup "$TABLE" | grep -q . || ip rule add to "$net" lookup "$TABLE" priority "$PRIORITY"
done
