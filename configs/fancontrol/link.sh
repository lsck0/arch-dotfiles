#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# software fan control lives on the desktop only: the ITE SuperIO + force_id are board-specific,
# so a no-op on the laptop and on guests. match either the board model or the Gigabyte vendor.
board_name=$(cat /sys/class/dmi/id/board_name 2>/dev/null || true)
board_vendor=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null || true)
if [[ "$board_name" != *X870E* && "$board_vendor" != *Gigabyte* ]]; then
    exit 0
fi

set -e

sudo install -m644 it87-modules-load.conf /etc/modules-load.d/it87.conf
sudo install -m644 it87-modprobe.conf /etc/modprobe.d/it87.conf

# lm_sensors.service only runs `sensors -s` + an optional modprobe, safe with no config present.
sudo systemctl enable lm_sensors.service

# load it87 now and generate the fancontrol curve, so a new system is quiet without a manual pwmconfig
sudo bash ./gen-fancontrol.sh || echo "fancontrol: setup deferred (it87 loads on the next boot), rerun fixfan.sh then" >&2
