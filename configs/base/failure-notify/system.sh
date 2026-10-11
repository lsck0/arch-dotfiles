#!/usr/bin/env bash

# a monthly lynis audit, reported through the journal to each admin's system-notify (link.sh)
command -v lynis >/dev/null 2>&1 || exit 0
install -Dm755 lynis-audit.sh /usr/local/bin/lynis-audit
unit_install lynis-audit.service lynis-audit.timer
systemctl enable lynis-audit.timer
