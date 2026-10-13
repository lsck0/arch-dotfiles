#!/usr/bin/env bash

unit_present nix-daemon.service || exit 0
# KillMode=process: a restart leaves running builds and client connections alone
# as the last command an unchanged drop-in's false would fail the module
if dropin_install nix-daemon.service 10-priority.conf; then systemctl try-restart nix-daemon.service; fi
