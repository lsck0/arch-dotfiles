#!/usr/bin/env bash

set -ex

systemctl --user enable pipewire-pulse.service
systemctl --user enable pipewire-pulse.socket

sudo systemctl disable getty@tty2.service
sudo systemctl enable avahi-daemon.service
sudo systemctl enable bluetooth.service
sudo systemctl enable cronie.service
sudo systemctl enable cups
sudo systemctl enable lactd
sudo systemctl enable ly@tty2.service
sudo systemctl enable open-fprintd-resume.service
sudo systemctl enable open-fprintd-suspend.service
sudo systemctl enable ossec-server.target
