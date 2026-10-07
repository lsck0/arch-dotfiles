#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

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
    sudo systemctl enable --now ModemManager.service
fi

source $DOTFILES/scripts/lib/platform.sh
source $DOTFILES/scripts/lib/secrets.sh
source $DOTFILES/scripts/lib/personal.sh

conf=/etc/NetworkManager/NetworkManager.conf
dropin=/etc/NetworkManager/conf.d/10-home-wired.conf
gateways=/etc/NetworkManager/home-gateways
personal=/etc/NetworkManager/personal
form=$(platform_form_factor "$DOTFILES")
# a restart drops wifi for seconds: only on change, then wait so later link.sh (nvim plugins) have network
changed=0
cmp -s NetworkManager.conf "${conf}" || changed=1
sudo install -Dm644 NetworkManager.conf "${conf}"
if [[ "${form}" == desktop ]]; then
    cmp -s home-wired.conf "${dropin}" || changed=1
    sudo install -Dm644 home-wired.conf "${dropin}"
elif [[ -e "${dropin}" ]]; then
    sudo rm -f "${dropin}"
    changed=1
fi
if ((changed)); then
    sudo systemctl restart NetworkManager.service
    nm-online -q --timeout=60 || echo "networkmanager: still offline after 60s" >&2
fi

# saved networks in secrets/wifi are home: their profiles keep the hardware mac and ipv6, every other network gets a
# random mac, and the persona dispatcher turns its ipv6 off
if secret_is_plaintext $DOTFILES/secrets/wifi; then
    while IFS=$'\t' read -r ssid _; do
        [[ -n "${ssid}" ]] || continue
        for uuid in $(nmcli -g UUID,TYPE connection show | sed -n 's/:802-11-wireless$//p'); do
            if [[ "$(nmcli -g 802-11-wireless.ssid connection show "${uuid}")" == "${ssid}" ]]; then
                sudo nmcli connection modify "${uuid}" 802-11-wireless.cloned-mac-address permanent ipv6.method auto
            fi
        done
    done <$DOTFILES/secrets/wifi
fi
# the desktop is only ever wired at home (home-wired.conf)
if [[ "${form}" == desktop ]] && is_personal; then
    for uuid in $(nmcli -g UUID,TYPE connection show | sed -n 's/:802-3-ethernet$//p'); do
        sudo nmcli connection modify "${uuid}" ipv6.method auto
    done
fi

# home is decided on these gateway macs (home-network.sh); without them no network is home
if is_personal && secret_is_plaintext $DOTFILES/secrets/home-gateways; then
    sudo install -o root -g root -m644 $DOTFILES/secrets/home-gateways "${gateways}"
else
    sudo rm -f "${gateways}"
fi
# luca's homelab ips fail fast off home (homelab-routes.sh)
if is_personal; then
    sudo install -o root -g root -m644 /dev/null "${personal}"
else
    sudo rm -f "${personal}"
fi

# NM refuses a group/world-writable dispatcher; they run in name order, so home is decided before the others read it
sudo install -o root -g root -m755 home-network.sh /etc/NetworkManager/dispatcher.d/70-home-network
sudo install -o root -g root -m755 homelab-routes.sh /etc/NetworkManager/dispatcher.d/80-homelab-routes
# untrusted-network lockdown: firewall, no mdns, no ipv6
sudo install -o root -g root -m755 persona-dispatcher.sh /etc/NetworkManager/dispatcher.d/90-anonymous-persona
