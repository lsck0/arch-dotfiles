#!/usr/bin/env bash

set -ex

if ! command -v nmcli >/dev/null 2>&1; then
    exit 0
fi

sudo ln -sf ${PWD}/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
sudo systemctl restart NetworkManager.service
