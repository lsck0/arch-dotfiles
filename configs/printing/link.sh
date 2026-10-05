#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/platform.sh
# cups also arrives under wsl, as a dependency of hermes-agent, where windows owns the printers
if ! command -v cupsd >/dev/null 2>&1 || [[ "$(platform_form_factor ../..)" == wsl ]]; then
    exit 0
fi

set -e

# cups.socket and avahi-daemon.socket are enabled in configs/systemd/link.sh, nothing starts at boot

# network printers advertise over mdns
if ! grep -q "mdns_minimal" /etc/nsswitch.conf; then
    sudo cp /etc/nsswitch.conf "/etc/nsswitch.conf.bak-$(date +%Y%m%d)"
    sudo sed -i 's|^hosts:.*|hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns|' /etc/nsswitch.conf
fi

# cups-pdf does not create the queue itself
if ! lpstat -p PDF >/dev/null 2>&1; then
    sudo lpadmin -p PDF -v cups-pdf:/ -m CUPS-PDF_opt.ppd -E
    sudo lpadmin -d PDF
fi
