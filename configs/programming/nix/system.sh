#!/usr/bin/env bash

unit_present nix-daemon.service || exit 0
# KillMode=process: a restart leaves running builds and client connections alone
if file_update nix-daemon-priority.conf /etc/systemd/system/nix-daemon.service.d/10-priority.conf; then
    systemctl daemon-reload
    systemctl try-restart nix-daemon.service
fi
