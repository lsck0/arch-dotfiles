#!/bin/env bash

set -ex

systemctl --user enable pipewire-pulse.service
systemctl --user enable pipewire-pulse.socket

sudo systemctl enable avahi-daemon.service
sudo systemctl enable bluetooth.target
sudo systemctl enable cronie.service
sudo systemctl enable cups
sudo systemctl enable ly.service
sudo systemctl enable ossec-server.target
