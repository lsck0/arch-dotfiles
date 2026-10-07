#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

command -v notify-send >/dev/null 2>&1 || exit 0

set -e

units="${HOME}/.config/systemd/user"
install -Dm644 failure-notify@.service "${units}/failure-notify@.service"
install -Dm644 failures-login.service "${units}/failures-login.service"
install -Dm644 failure-notify.conf "${units}/service.d/10-failure-notify.conf"
# the handler must not be its own OnFailure=
mkdir -p "${units}/failure-notify@.service.d"
ln -sfn /dev/null "${units}/failure-notify@.service.d/10-failure-notify.conf"
systemctl --user daemon-reload
# not --now: config.sh's own empty FAILURES.config exists while it runs
systemctl --user enable failures-login.service
