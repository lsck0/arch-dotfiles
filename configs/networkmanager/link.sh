#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v nmcli >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo ln -sfn ${PWD}/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf

sudo systemctl restart NetworkManager.service
