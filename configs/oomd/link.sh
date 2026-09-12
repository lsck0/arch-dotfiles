#!/usr/bin/env bash

set -ex

if [[ ! -x ${PWD}/oom-notify.sh ]]; then
    exit 0
fi

sudo systemctl enable systemd-oomd.service

# scope oomd's kill authority to app.slice only, Hyprland itself stays ineligible
sudo ln -sf ${PWD}/oomd.conf /etc/systemd/oomd.conf.d/10-oomd.conf
mkdir -p ${HOME}/.config/systemd/user/app.slice.d
ln -sf ${PWD}/oomd-app.slice.conf ${HOME}/.config/systemd/user/app.slice.d/10-oomd.conf

# desktop notification whenever oomd or the kernel OOM killer kills
chmod 755 ${PWD}/oom-notify.sh
install -Dm644 ${PWD}/oom-notify.service ${HOME}/.config/systemd/user/oom-notify.service
systemctl --user daemon-reload
systemctl --user enable --now oom-notify.service
