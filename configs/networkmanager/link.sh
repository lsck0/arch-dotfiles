#!/usr/bin/env bash

set -ex

sudo ln -sf ${PWD}/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
sudo systemctl restart NetworkManager.service
