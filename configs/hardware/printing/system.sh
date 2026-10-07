#!/usr/bin/env bash

PDF_QUEUE=PDF
SYNC=/usr/local/bin/printers-sync
# after 90-anonymous-persona, which starts avahi on a home up
DISPATCHER=/etc/NetworkManager/dispatcher.d/95-printers-sync

# cups also arrives under wsl, as a dependency of hermes-agent, where windows owns the printers
if ! command -v cupsd >/dev/null 2>&1 || [[ "$FORM_FACTOR" == wsl ]]; then
    exit 0
fi

# cups.socket and avahi-daemon.socket are enabled in configs/base/systemd, nothing starts at boot; on the run that
# installed cups the socket is not listening yet, and lpstat/lpadmin below need it
systemctl start cups.socket

# network printers advertise over mdns
if ! grep -q "mdns_minimal" /etc/nsswitch.conf; then
    cp /etc/nsswitch.conf "/etc/nsswitch.conf.bak-$(date +%Y%m%d)"
    sed -i 's|^hosts:.*|hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns|' /etc/nsswitch.conf
fi

# cups-pdf does not create the queue itself; not the default, a real printer takes that (printers-sync)
lpstat -p "$PDF_QUEUE" >/dev/null 2>&1 || lpadmin -p "$PDF_QUEUE" -v cups-pdf:/ -m CUPS-PDF_opt.ppd -E || true

install -Dm755 printers-sync.sh "$SYNC"
unit_install printers-sync.service
# NM refuses a group/world-writable dispatcher
install -o root -g root -m755 printers-dispatcher.sh "$DISPATCHER"
# off home avahi is masked and nothing is found; the next home connect catches up
"$SYNC" || echo "printing: some printers found over mdns got no queue, see above" >&2

lpstat -v 2>/dev/null | grep -q ' dnssd://' \
    || echo "printing: no driverless printer queue yet, one appears on the next home connect that finds a printer" >&2
if ! lpstat -p "$PDF_QUEUE" >/dev/null 2>&1; then
    echo "printing: no $PDF_QUEUE queue" >&2
    exit 1
fi
