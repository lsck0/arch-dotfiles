#!/usr/bin/env bash

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
