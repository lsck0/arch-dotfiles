#!/usr/bin/env bash

if [[ ! -f ${PWD}/config.json ]]; then
    exit 0
fi

set -ex

sudo ln -sf ${PWD}/config.json /var/lib/portmaster/config.json

if [[ -f /etc/xdg/autostart/portmaster-autostart.desktop ]]; then
    mkdir -p "${HOME}/.config/autostart"
    ln -sf "${PWD}/portmaster-autostart.desktop" "${HOME}/.config/autostart/portmaster-autostart.desktop"
fi
