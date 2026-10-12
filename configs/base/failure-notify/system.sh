#!/usr/bin/env bash

# a monthly lynis audit, reported through the journal to each admin's system-notify (link.sh)
command -v lynis >/dev/null 2>&1 || exit 0
file_update lynis-audit.sh /usr/local/bin/lynis-audit 755
unit_install lynis-audit.service lynis-audit.timer
systemctl enable lynis-audit.timer
