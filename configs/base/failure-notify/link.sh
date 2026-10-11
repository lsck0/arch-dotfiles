#!/usr/bin/env bash

command -v notify-send >/dev/null 2>&1 || exit 0

# OnFailure= for every user service; the handler must not be its own OnFailure=
install -Dm644 failure-notify.conf "${UNIT_DIR}/service.d/10-failure-notify.conf"
mkdir -p "${UNIT_DIR}/failure-notify@.service.d"
ln -sfn /dev/null "${UNIT_DIR}/failure-notify@.service.d/10-failure-notify.conf"
link_commands system-notify.sh update-check.sh
unit_install failure-notify@.service failures-login.service system-notify.service update-check.service update-check.timer
# not --now: config.sh's own empty FAILURES.config exists while it runs
systemctl --user enable failures-login.service
# system units, smartd and lynis-audit report through the system journal, which wheel reads
systemctl --user enable system-notify.service
systemctl --user restart system-notify.service
if command -v checkupdates >/dev/null 2>&1; then
    systemctl --user enable update-check.timer
else
    systemctl --user disable update-check.timer 2>/dev/null || true
fi
