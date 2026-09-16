#!/usr/bin/env bash

cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

chmod 755 ${PWD}/ntfy-notify.py
install -Dm644 ${PWD}/ntfy-notify.service ${HOME}/.config/systemd/user/ntfy-notify.service
systemctl --user daemon-reload
systemctl --user enable --now ntfy-notify.service
