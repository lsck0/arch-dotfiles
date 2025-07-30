#!/bin/env bash

set -ex

mkdir -p ~/.config/systemd/user/

ln -sf ${PWD}/headset-volume.service ~/.config/systemd/user/headset-volume.service
ln -sf ${PWD}/headset-volume.timer ~/.config/systemd/user/headset-volume.timer

systemctl --user enable headset-volume.timer
