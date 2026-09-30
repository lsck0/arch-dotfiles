#!/usr/bin/env bash

if [[ ! -x /usr/bin/netscanner ]]; then
    exit 0
fi

set -e

# cap_net_raw instead of setuid root, reapplied on upgrade by pacman/hooks/netscanner-setcap.hook
sudo chmod u-s /usr/bin/netscanner
sudo setcap cap_net_raw+ep /usr/bin/netscanner
