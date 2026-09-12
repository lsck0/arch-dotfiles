#!/usr/bin/env bash

if [[ ! -x /bin/netscanner ]]; then
    exit 0
fi

set -ex

sudo chown root:$USER /bin/netscanner
sudo chmod u+s /bin/netscanner
