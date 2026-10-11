#!/usr/bin/env bash

# windows owns kernel, boot, drivers, power, audio and network under wsl; nothing here applies
[[ "$FORM_FACTOR" != wsl ]] || exit 0

if [[ "$FORM_FACTOR" == laptop ]]; then
    conf=bat.tlp.conf
else
    conf=ac-only.tlp.conf
fi

systemctl enable tlp.service
# copy, tlp.service has ProtectHome and cannot follow a link into /home
if file_update "$conf" /etc/tlp.conf; then
    systemctl restart tlp.service
else
    systemctl start tlp.service
fi
