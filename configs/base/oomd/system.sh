#!/usr/bin/env bash

unit_present systemd-oomd.service || exit 0
systemctl enable systemd-oomd.service
# oomd may only kill in app.slice, never hyprland itself; copied, systemd-oomd starts before /home mounts
rm -f /etc/systemd/oomd.conf.d/10-oomd.conf
install -Dm644 oomd.conf /etc/systemd/oomd.conf.d/10-oomd.conf
