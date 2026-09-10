#!/usr/bin/env bash

set -ex

# polkit rule — needs root. Without it the user timer's timedatectl call
# raises a prompt nothing can answer, and the timer fails every hour instead
# of doing its job.
sudo ln -sf ${PWD}/49-timezone-auto.rules /etc/polkit-1/rules.d/49-timezone-auto.rules

mkdir -p ${HOME}/.config/systemd/user
ln -sf ${PWD}/timezone-auto.service ${HOME}/.config/systemd/user/timezone-auto.service
ln -sf ${PWD}/timezone-auto.timer ${HOME}/.config/systemd/user/timezone-auto.timer
systemctl --user daemon-reload
systemctl --user enable --now timezone-auto.timer

# Show what it would do right now without changing anything.
${PWD}/timezone-auto.sh check || true
