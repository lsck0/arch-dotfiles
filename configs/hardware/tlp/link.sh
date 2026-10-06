#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -e

sudo systemctl enable tlp.service

source ../../../scripts/lib/platform.sh
form_factor=$(platform_form_factor ../../..)
if [[ "$form_factor" == laptop ]]; then
    conf=bat.tlp.conf
else
    conf=ac-only.tlp.conf
fi

# copy, tlp.service has ProtectHome and cannot follow a link into /home
sudo install -m 644 "${PWD}/${conf}" /etc/tlp.conf
sudo systemctl restart tlp
