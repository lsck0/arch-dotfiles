#!/usr/bin/env bash

unit_present nix-daemon.service || exit 0
# KillMode=process: a restart leaves running builds and client connections alone
dropin_install nix-daemon.service 10-priority.conf && systemctl try-restart nix-daemon.service
