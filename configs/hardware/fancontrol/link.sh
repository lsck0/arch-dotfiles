#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/platform.sh
form_factor=$(platform_form_factor "$DOTFILES") || exit 1
[[ "$form_factor" == desktop ]] || exit 0

# force_id and the fan curve fit exactly this board and its 9950X3D
BOARD_NAME="X870E AORUS ELITE WIFI7"
[[ "$(</sys/class/dmi/id/board_name)" == "$BOARD_NAME" ]] || exit 0

set -e

sudo install -m644 it87-modules-load.conf /etc/modules-load.d/it87.conf
sudo install -m644 it87-modprobe.conf /etc/modprobe.d/it87.conf

# lm_sensors.service only runs `sensors -s` + an optional modprobe, safe with no config present.
sudo systemctl enable lm_sensors.service

# fancontrol-gen.service (unsandboxed oneshot) rebuilds /etc/fancontrol for the live hwmon numbering before fancontrol reads it, so a hwmonN reshuffle never breaks it; fancontrol keeps ProtectSystem=full (read-only), which is why the regen cannot be its own ExecStartPre
sudo install -m755 gen-fancontrol.sh /usr/local/bin/gen-fancontrol
sudo install -m644 fancontrol-gen.service /etc/systemd/system/fancontrol-gen.service
sudo install -Dm644 fancontrol-regen.conf /etc/systemd/system/fancontrol.service.d/regen.conf
sudo systemctl daemon-reload
sudo systemctl enable fancontrol-gen.service
sudo systemctl enable --now fancontrol.service
