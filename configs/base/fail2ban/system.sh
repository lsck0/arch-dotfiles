#!/usr/bin/env bash

# windows owns kernel, boot, drivers, power, audio and network under wsl; nothing here applies
[[ "$FORM_FACTOR" != wsl ]] || exit 0

systemctl enable fail2ban.service
if file_update jail.local /etc/fail2ban/jail.local; then
    # 1.1.1's reload drops a changed banaction instead of swapping it, bans persist in its db
    systemctl restart fail2ban.service
else
    systemctl start fail2ban.service
fi
