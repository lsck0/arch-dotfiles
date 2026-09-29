#!/usr/bin/env bash

if [[ ! -x /bin/netscanner ]]; then
    exit 0
fi

set -ex

# cap_net_raw instead of setuid root
sudo chown root:root /bin/netscanner
sudo chmod u-s /bin/netscanner
sudo setcap cap_net_raw+ep /bin/netscanner
