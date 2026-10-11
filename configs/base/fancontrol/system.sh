#!/usr/bin/env bash

# force_id and the fan curve fit exactly this board and its 9950X3D
BOARD_NAME="X870E AORUS ELITE WIFI7"
[[ "$FORM_FACTOR" == desktop && "$(</sys/class/dmi/id/board_name)" == "$BOARD_NAME" ]] || exit 0

install -m644 it87-modules-load.conf /etc/modules-load.d/it87.conf
install -m644 it87-modprobe.conf /etc/modprobe.d/it87.conf

# lm_sensors.service only runs `sensors -s` + an optional modprobe, safe with no config present.
systemctl enable lm_sensors.service

# fancontrol-gen.service (unsandboxed oneshot) rebuilds /etc/fancontrol for the live hwmon numbering before fancontrol reads it, so a hwmonN reshuffle never breaks it; fancontrol keeps ProtectSystem=full (read-only), which is why the regen cannot be its own ExecStartPre
install -m755 gen-fancontrol.sh /usr/local/bin/gen-fancontrol
install -Dm644 fancontrol-regen.conf /etc/systemd/system/fancontrol.service.d/regen.conf
unit_install fancontrol-gen.service
systemctl enable fancontrol-gen.service
systemctl enable --now fancontrol.service
