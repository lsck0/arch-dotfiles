#!/usr/bin/env bash

set -ex

sudo ln -sf ${PWD}/99-powercap-readable.rules /etc/udev/rules.d/99-powercap-readable.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=powercap
