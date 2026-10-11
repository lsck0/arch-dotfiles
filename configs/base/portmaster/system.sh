#!/usr/bin/env bash
# global rules, portmaster's config file has no per-app ones: mdns (avahi-daemon) both ways and ipp/ipps (cupsd) out,
# lan only; off home avahi is masked and nothing on the lan answers. lists: its defaults plus ADS; UNBREAK carries
# portmaster's exceptions for services the other lists break

if [[ ! -d /var/lib/portmaster ]]; then
    echo "portmaster: /var/lib/portmaster missing, skipping" >&2
    exit 0
fi

file_update cleanup.conf /etc/systemd/system/portmaster.service.d/cleanup.conf && systemctl daemon-reload

# copy, ProtectHome=read-only blocks portmaster saving through a link into /home
if file_update config.json /var/lib/portmaster/config.json; then
    # read at start only; stays stopped while toggle-protonvpn.sh or toggle-firewall.sh holds it off
    systemctl try-restart portmaster.service
fi

# loopback, pentest vpns and the pentest group skip its per-connection queue; see portmaster-bypass.nft
install -Dm644 portmaster-bypass.nft /etc/nftables.d/portmaster-bypass.nft
unit_install portmaster-bypass.service
systemctl enable portmaster-bypass.service
systemctl reload-or-restart portmaster-bypass.service
