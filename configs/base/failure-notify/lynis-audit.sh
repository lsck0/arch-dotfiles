#!/usr/bin/env bash
# monthly lynis audit: the hardening index and the first warnings go to the journal as dotfiles-health, which each
# admin's system-notify shows; the full report stays in /var/log/lynis-report.dat
set -euo pipefail

REPORT=/var/log/lynis-report.dat

lynis audit system --cronjob --quiet >/dev/null
index=$(sed -n 's/^hardening_index=//p' "$REPORT")
# warning[]=<test>|<text>|<details>|<solution>|
mapfile -t warnings < <(sed -n 's/^warning\[\]=//p' "$REPORT" | cut -d'|' -f1,2 | tr '|' ' ')
body="hardening index ${index:-unknown}, ${#warnings[@]} warnings"
((${#warnings[@]} == 0)) || body+=": $(printf '%s; ' "${warnings[@]:0:5}")"
logger -t dotfiles-health -p user.notice "Lynis audit: $body (lynis show details <test>)"
