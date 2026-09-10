#!/usr/bin/env bash

set -ex

# cups + avahi are installed above but do nothing until enabled.
sudo systemctl enable --now cups.service avahi-daemon.service || true

# Network printers advertise over mDNS. avahi alone is not enough: glibc only
# resolves `.local` names if nsswitch consults mdns_minimal, which must come
# before `resolve` and carry [NOTFOUND=return] so ordinary lookups still fall
# through to DNS. Idempotent — only rewrites the line if mdns is absent.
if ! grep -q "mdns_minimal" /etc/nsswitch.conf; then
    sudo cp /etc/nsswitch.conf /etc/nsswitch.conf.bak-$(date +%Y%m%d)
    sudo sed -i 's|^hosts:.*|hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns|' /etc/nsswitch.conf
fi

# cups-pdf ships the backend and PPD but does not create the queue itself, so
# without this there is still no printer at all on a machine with no hardware.
if ! lpstat -p PDF >/dev/null 2>&1; then
    sudo lpadmin -p PDF -v cups-pdf:/ -m CUPS-PDF_opt.ppd -E || true
    sudo lpadmin -d PDF || true
fi
