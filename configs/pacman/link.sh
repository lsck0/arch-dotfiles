#!/usr/bin/env bash

set -ex

sudo ln -sf ${PWD}/pacman.conf /etc/pacman.conf

sudo mkdir -p /etc/pacman.d/hooks
for hook in ${PWD}/hooks/*.hook; do
    sudo ln -sf "${hook}" /etc/pacman.d/hooks/$(basename "${hook}")
done

# cache cleaning for pacman and yay
mkdir -p "${HOME}/.config/systemd/user"

if command -v paccache >/dev/null 2>&1; then
    systemctl --user enable --now yay-cache-clean.timer
fi

ln -sf "${PWD}/yay-cache-clean.service" "${HOME}/.config/systemd/user/yay-cache-clean.service"
ln -sf "${PWD}/yay-cache-clean.timer" "${HOME}/.config/systemd/user/yay-cache-clean.timer"

systemctl --user daemon-reload
