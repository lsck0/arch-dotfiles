#!/usr/bin/env bash
# disk health; smartd.service skips itself in a vm (ConditionVirtualization=no)

command -v smartd >/dev/null 2>&1 || exit 0

# no smart-capable disk (emmc): smartd would exit with an error on every boot
if [[ -z "$(smartctl --scan)" ]]; then
    systemctl disable --now smartd.service 2>/dev/null || true
    exit 0
fi

systemctl enable smartd.service
if file_update smartd.conf /etc/smartd.conf; then
    systemctl restart smartd.service
else
    systemctl start smartd.service
fi
