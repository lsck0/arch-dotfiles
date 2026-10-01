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

# the module loads on next boot (modules-load.d); not modprobed here on purpose, loading a forced
# SuperIO driver against the running system is a state change left for the reboot.
sudo install -m644 it87-modules-load.conf /etc/modules-load.d/it87.conf
sudo install -m644 it87-modprobe.conf /etc/modprobe.d/it87.conf

# lm_sensors.service only runs `sensors -s` + an optional modprobe, safe with no config present.
sudo systemctl enable lm_sensors.service

# an unconfigured fancontrol can stop a fan, so enable it only once a validated /etc/fancontrol exists
if [[ -s /etc/fancontrol ]]; then
    sudo systemctl enable fancontrol.service
else
    echo "fancontrol: reboot, then run 'sudo pwmconfig' once to build /etc/fancontrol, then 'sudo systemctl enable --now fancontrol'"
fi
