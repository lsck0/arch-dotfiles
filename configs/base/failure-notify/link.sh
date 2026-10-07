#!/usr/bin/env bash

command -v notify-send >/dev/null 2>&1 || exit 0

# OnFailure= for every user service; the handler must not be its own OnFailure=
install -Dm644 failure-notify.conf "${UNIT_DIR}/service.d/10-failure-notify.conf"
mkdir -p "${UNIT_DIR}/failure-notify@.service.d"
ln -sfn /dev/null "${UNIT_DIR}/failure-notify@.service.d/10-failure-notify.conf"
unit_install failure-notify@.service failures-login.service
# not --now: config.sh's own empty FAILURES.config exists while it runs
systemctl --user enable failures-login.service
