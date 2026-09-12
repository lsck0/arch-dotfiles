#!/usr/bin/env bash

set -ex

if ! systemctl list-unit-files --no-legend python3-validity.service 2>/dev/null | grep -q .; then
    exit 0
fi

sudo mkdir -p /etc/systemd/system/python3-validity.service.d
sudo ln -sf ${PWD}/python3-validity-override.conf /etc/systemd/system/python3-validity.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl enable python3-validity.service
