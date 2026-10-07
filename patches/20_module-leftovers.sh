#!/usr/bin/env bash
# drop files modules once installed and their system.sh no longer removes on every run: limine's deploy hook, the i2c
# rule ddcutil's uaccess replaced, tor-router's dropin, the old tablet rule, the spicetify hook that ran a user's checkout as
# root, and networkmanager's personal marker (now homelab, gated on the machine fact)
set -euo pipefail

HOOKS=(/etc/pacman.d/hooks/limine-deploy.hook /etc/pacman.d/hooks/spicetify-reapply.hook)
UDEV_RULES=(/etc/udev/rules.d/60-ddcutil-i2c.rules /etc/udev/rules.d/99-graphics-tablet.rules)
TOR_ROUTER_DROPIN=/etc/systemd/system/tor-router.service.d
NM_PERSONAL_MARKER=/etc/NetworkManager/personal

rm -f "${HOOKS[@]}" "$NM_PERSONAL_MARKER"
udev_changed=0
for rule in "${UDEV_RULES[@]}"; do
    [[ -e "$rule" ]] || continue
    rm -f "$rule"
    udev_changed=1
done
if ((udev_changed)); then udevadm control --reload-rules; fi
if [[ -e "$TOR_ROUTER_DROPIN" ]]; then
    rm -rf "$TOR_ROUTER_DROPIN"
    systemctl daemon-reload
fi
