#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! systemctl list-unit-files --no-legend systemd-oomd.service | grep -q .; then
    exit 0
fi

set -e

sudo systemctl enable systemd-oomd.service

# oomd may only kill in app.slice, never hyprland itself; copied not linked because systemd-oomd starts before /home mounts
sudo rm -f /etc/systemd/oomd.conf.d/10-oomd.conf
sudo install -Dm644 "${PWD}/oomd.conf" /etc/systemd/oomd.conf.d/10-oomd.conf
mkdir -p "${HOME}/.config/systemd/user/app.slice.d"
ln -sfn "${PWD}/oomd-app.slice.conf" "${HOME}/.config/systemd/user/app.slice.d/10-oomd.conf"

install -Dm644 "${PWD}/oom-notify.service" "${HOME}/.config/systemd/user/oom-notify.service"
systemctl --user daemon-reload
systemctl --user enable --now oom-notify.service
