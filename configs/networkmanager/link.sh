#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v nmcli >/dev/null 2>&1; then
    exit 0
fi

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

conf=/etc/NetworkManager/NetworkManager.conf
# a restart drops wifi for seconds: only on change, then wait so later link.sh (nvim plugins) have network
changed=0
cmp -s NetworkManager.conf "${conf}" || changed=1
sudo install -Dm644 NetworkManager.conf "${conf}"
if ((changed)); then
    sudo systemctl restart NetworkManager.service
    nm-online -q --timeout=60 || echo "networkmanager: still offline after 60s" >&2
fi
