#!/usr/bin/env bash

if [[ ! -d /etc/polkit-1/rules.d ]]; then
    exit 0
fi

set -ex

mkdir -p ${HOME}/.config/systemd/user

ln -sf ${PWD}/timezone-auto.service ${HOME}/.config/systemd/user/timezone-auto.service
ln -sf ${PWD}/timezone-auto.timer ${HOME}/.config/systemd/user/timezone-auto.timer
sudo ln -sf ${PWD}/49-timezone-auto.rules /etc/polkit-1/rules.d/49-timezone-auto.rules

systemctl --user daemon-reload
systemctl --user enable --now timezone-auto.timer

${PWD}/timezone-auto.sh check || true
