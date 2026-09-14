#!/usr/bin/env bash

if ! command -v nmcli >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo ln -sfn ${PWD}/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf

sudo systemctl restart NetworkManager.service
