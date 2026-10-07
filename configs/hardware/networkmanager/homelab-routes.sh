#!/usr/bin/env bash
# NM dispatcher: on a home link (/run/home-network) the homelab subnets route straight out the lan from their own
# table, looked up ahead of a full-tunnel vpn's rules (wg-quick, NM wireguard); wg0's main-table routes stay untouched,
# so they hold again once home is left; virbr0 nat follows. on luca's machines an unreachable fallback catches the rest
iface="${1:-}"
action="${2:-}"
case "$action" in up | dhcp4-change | down) ;; *) exit 0 ;; esac

HOMELAB_NETS="10.100.0.0/16 10.200.0.0/16"
TABLE=178
# below wg-quick's suppress_prefixlength 0 rule (32764) and NM wireguard's
PRIORITY=30000
# behind wg0's main-table routes; off home and wg0 the homelab fails fast instead of leaking out the default route
UNREACHABLE_METRIC=4000
HOME_NETWORK=/run/home-network
PERSONAL=/etc/NetworkManager/personal

# physical wifi/ethernet only
[ -e "/sys/class/net/${iface}/device" ] || exit 0

if [ "$action" = down ]; then
    ip route flush table "$TABLE" dev "$iface" 2>/dev/null
    ip route show table "$TABLE" 2>/dev/null | grep -q . && exit 0
    for net in $HOMELAB_NETS; do
        ip rule del to "$net" lookup "$TABLE" priority "$PRIORITY" 2>/dev/null
    done
    exit 0
fi

if [ -e "$PERSONAL" ]; then
    for net in $HOMELAB_NETS; do
        ip route replace unreachable "$net" metric "$UNREACHABLE_METRIC"
    done
fi

grep -qx "$iface" "$HOME_NETWORK" 2>/dev/null || exit 0
gw=$(ip -4 route show default dev "$iface" | awk '{print $3; exit}')
[ -n "$gw" ] || exit 0
for net in $HOMELAB_NETS; do
    ip route replace "$net" via "$gw" dev "$iface" table "$TABLE"
    ip rule list to "$net" lookup "$TABLE" | grep -q . || ip rule add to "$net" lookup "$TABLE" priority "$PRIORITY"
done
