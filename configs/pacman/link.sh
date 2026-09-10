#!/usr/bin/env bash

set -ex

sudo ln -sf ${PWD}/pacman.conf /etc/pacman.conf

sudo mkdir -p /etc/pacman.d/hooks
for hook in ${PWD}/hooks/*.hook; do
    sudo ln -sf "${hook}" /etc/pacman.d/hooks/$(basename "${hook}")
done

# yay's build/download cache is user-owned and is cleaned weekly. The unit
# files are linked below; enabling a timer does not require a reboot.
mkdir -p "${HOME}/.config/systemd/user"
ln -sf "${PWD}/yay-cache-clean.service" "${HOME}/.config/systemd/user/yay-cache-clean.service"
ln -sf "${PWD}/yay-cache-clean.timer" "${HOME}/.config/systemd/user/yay-cache-clean.timer"
systemctl --user daemon-reload
systemctl --user enable --now yay-cache-clean.timer
