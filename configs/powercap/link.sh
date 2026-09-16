#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v udevadm >/dev/null 2>&1; then
    exit 0
fi

set -ex

sudo ln -sfn ${PWD}/99-powercap-readable.rules /etc/udev/rules.d/99-powercap-readable.rules

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=powercap
