#!/usr/bin/env bash
# Scheduled $HOME backup. Only a homelab user has the NAS to back up to; a guest or an off-homelab box gets nothing.

command -v borg >/dev/null 2>&1 || exit 0

if profile_has homelab; then
    link_commands borg-backup.sh
    unit_install borg-backup.service borg-backup.timer
    systemctl --user enable borg-backup.timer
else
    systemctl --user disable --now borg-backup.timer 2>/dev/null || true
fi
