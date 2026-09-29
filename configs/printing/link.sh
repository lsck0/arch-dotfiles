#!/usr/bin/env bash

set -ex

if ! command -v cupsd >/dev/null 2>&1; then
    exit 0
fi

sudo systemctl enable --now cups.service || true
command -v avahi-daemon >/dev/null 2>&1 && sudo systemctl enable --now avahi-daemon.service || true

# network printers advertise over mdns
if ! grep -q "mdns_minimal" /etc/nsswitch.conf; then
    sudo cp /etc/nsswitch.conf "/etc/nsswitch.conf.bak-$(date +%Y%m%d)"
    sudo sed -i 's|^hosts:.*|hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns|' /etc/nsswitch.conf
fi

# cups-pdf does not create the queue itself
if ! lpstat -p PDF >/dev/null 2>&1; then
    sudo lpadmin -p PDF -v cups-pdf:/ -m CUPS-PDF_opt.ppd -E || true
    sudo lpadmin -d PDF || true
fi
