#!/usr/bin/env bash

# windows owns kernel, boot, drivers, power, audio and network under wsl; nothing here applies
[[ "$FORM_FACTOR" != wsl ]] || exit 0

install -Dm644 v4l2loopback.conf /etc/modules-load.d/v4l2loopback.conf
install -Dm644 v4l2loopback-options.conf /etc/modprobe.d/v4l2loopback.conf
