#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! systemctl list-unit-files --no-legend systemd-oomd.service | grep -q .; then
    exit 0
fi

set -e

sudo systemctl enable systemd-oomd.service

# oomd may only kill in app.slice, never hyprland itself
sudo mkdir -p /etc/systemd/oomd.conf.d
sudo ln -sfn "${PWD}/oomd.conf" /etc/systemd/oomd.conf.d/10-oomd.conf
mkdir -p "${HOME}/.config/systemd/user/app.slice.d"
ln -sfn "${PWD}/oomd-app.slice.conf" "${HOME}/.config/systemd/user/app.slice.d/10-oomd.conf"

chmod 755 "${PWD}/oom-notify.sh"
install -Dm644 "${PWD}/oom-notify.service" "${HOME}/.config/systemd/user/oom-notify.service"
systemctl --user daemon-reload
systemctl --user enable --now oom-notify.service
