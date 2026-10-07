#!/usr/bin/env bash

CONF=/etc/NetworkManager/NetworkManager.conf
DROPIN=/etc/NetworkManager/conf.d/10-home-wired.conf
DISPATCHERS=/etc/NetworkManager/dispatcher.d
# home is decided on these gateway macs (home-network.sh); without them no network is home
GATEWAYS=/etc/NetworkManager/home-gateways
# homelab-routes.sh fails the homelab ips fast off home on a HOMELAB machine
HOMELAB_MARKER=/etc/NetworkManager/homelab
GATEWAYS_SECRET="$DOTFILES_SECRETS/home-gateways"
WIFI_SECRET="$DOTFILES_SECRETS/wifi"
MAC_PATTERN='^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'
ONLINE_TIMEOUT_S=60

# a qmi/mbim modem creates a wwan*/wwp* iface and a cdc-wdm node; not ID_MM_CANDIDATE, it tags every probeable serial port
has_modem() {
    local dev
    for dev in /sys/class/net/wwan* /sys/class/net/wwp* /dev/cdc-wdm*; do
        [ -e "$dev" ] && return 0
    done
    command -v mmcli >/dev/null 2>&1 && mmcli -L 2>/dev/null | grep -q '/Modem/' && return 0
    nmcli -t -f TYPE device 2>/dev/null | grep -qx gsm && return 0
    return 1
}
# ModemManager drives nmcli radio wwan (toggle-mobile); only run it with a modem, else idle overhead
if command -v ModemManager >/dev/null 2>&1 && has_modem; then
    systemctl enable --now ModemManager.service
fi

# a restart drops wifi for seconds: only on change, then wait so later modules have network
changed=0
file_update NetworkManager.conf "$CONF" && changed=1
# the desktop is only ever wired at home, so its ethernet keeps the hardware mac. a laptop's ethernet stays random on
# every wired network, its home included: home-network.sh then never sees it as home (fail closed, locked down). NM's
# one auto-created wired profile serves every wired network, so a permanent mac there would follow it everywhere; a
# guest whose home is wired marks that one profile: nmcli connection modify <uuid> 802-3-ethernet.cloned-mac-address permanent
if [[ "$FORM_FACTOR" == desktop ]]; then
    file_update home-wired.conf "$DROPIN" && changed=1
elif [[ -e "$DROPIN" ]]; then
    rm -f "$DROPIN"
    changed=1
fi
if ((changed)); then
    systemctl restart NetworkManager.service
    nm-online -q --timeout="$ONLINE_TIMEOUT_S" || echo "networkmanager: still offline after ${ONLINE_TIMEOUT_S}s" >&2
fi

# saved networks in the wifi secret are home: their profiles keep the hardware mac and ipv6, every other network gets
# a random mac, and the persona dispatcher turns its ipv6 off. the ssid is only ever compared, never an nmcli argument
if [[ -f "$WIFI_SECRET" ]]; then
    while IFS=$'\t' read -r ssid _; do
        [[ -n "$ssid" ]] || continue
        for uuid in $(nmcli -g UUID,TYPE connection show | sed -n 's/:802-11-wireless$//p'); do
            if [[ "$(nmcli -g 802-11-wireless.ssid connection show "$uuid")" == "$ssid" ]]; then
                nmcli connection modify "$uuid" 802-11-wireless.cloned-mac-address permanent ipv6.method auto
            fi
        done
    done <"$WIFI_SECRET"
fi
# a HOMELAB desktop is only ever wired at home (home-wired.conf)
if [[ "$FORM_FACTOR" == desktop && -n "$HOMELAB" ]]; then
    for uuid in $(nmcli -g UUID,TYPE connection show | sed -n 's/:802-3-ethernet$//p'); do
        nmcli connection modify "$uuid" ipv6.method auto
    done
fi

# NM refuses a group/world-writable dispatcher; they run in name order, so home is decided before the others read it
install -o root -g root -m755 home-network.sh "$DISPATCHERS/70-home-network"
install -o root -g root -m755 homelab-routes.sh "$DISPATCHERS/80-homelab-routes"
# untrusted-network lockdown: firewall, no mdns, no ipv6
install -o root -g root -m755 persona-dispatcher.sh "$DISPATCHERS/90-anonymous-persona"

if [[ -n "$HOMELAB" ]]; then
    install -o root -g root -m644 /dev/null "$HOMELAB_MARKER"
else
    rm -f "$HOMELAB_MARKER"
fi

# the admin's secret replaces the list; never deleted: a run without secrets keeps it, and a guest's comes from
# bootstrap.sh's home question
if [[ -f "$GATEWAYS_SECRET" ]]; then
    # comments and blanks never equal a mac in home-network.sh's whole-line match, so they may stay
    if grep -qvE "$MAC_PATTERN|^(#.*)?$" "$GATEWAYS_SECRET" || ! grep -qE "$MAC_PATTERN" "$GATEWAYS_SECRET"; then
        echo "networkmanager: home-gateways is not one mac address per line, keeping $GATEWAYS" >&2
        exit 1
    fi
    install -o root -g root -m644 "$GATEWAYS_SECRET" "$GATEWAYS"
fi
