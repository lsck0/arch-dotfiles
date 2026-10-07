#!/usr/bin/env bash

unit_present systemd-oomd.service || exit 0
# the first enable also starts it, later runs leave a stop from the oom-protection toggle alone
if systemctl is-enabled -q systemd-oomd.service; then started=0; else systemctl enable --now systemd-oomd.service; started=1; fi
# oomd may only kill in app.slice, never hyprland itself; copied, systemd-oomd starts before /home mounts
# a running oomd reads its config only on start, so a change restarts it, a stopped one stays stopped
if file_update oomd.conf /etc/systemd/oomd.conf.d/10-oomd.conf && ((!started)); then
    systemctl try-restart systemd-oomd.service
fi
