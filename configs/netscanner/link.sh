#!/usr/bin/env bash

if [[ ! -x /bin/netscanner ]]; then
    exit 0
fi

set -ex

# cap_net_raw instead of setuid-root: netscanner only needs raw sockets for
# ARP/port scans; setuid-root would make any flaw a local root escalation.
sudo chown root:root /bin/netscanner
sudo chmod u-s /bin/netscanner
sudo setcap cap_net_raw+ep /bin/netscanner
