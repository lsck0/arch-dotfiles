#!/usr/bin/env bash

set -ex

sudo mkdir -p /etc/systemd/system/python3-validity.service.d
sudo ln -sf ${PWD}/python3-validity-override.conf /etc/systemd/system/python3-validity.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl enable python3-validity.service
