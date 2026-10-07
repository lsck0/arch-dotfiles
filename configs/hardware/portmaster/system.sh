#!/usr/bin/env bash
# global rules, portmaster's config file has no per-app ones: mdns (avahi-daemon) both ways and ipp/ipps (cupsd) out,
# lan only; off home avahi is masked and nothing on the lan answers

if [[ ! -d /var/lib/portmaster ]]; then
    echo "portmaster: /var/lib/portmaster missing, skipping" >&2
    exit 0
fi

# copy, ProtectHome=read-only blocks portmaster saving through a link into /home
if file_update config.json /var/lib/portmaster/config.json; then
    # read at start only; stays stopped while toggle-protonvpn.sh or toggle-firewall.sh holds it off
    systemctl try-restart portmaster.service
fi
