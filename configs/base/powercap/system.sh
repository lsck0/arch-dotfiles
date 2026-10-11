#!/usr/bin/env bash

# udevadm comes with systemd everywhere, wsl included, where windows owns the hardware
if ! command -v udevadm >/dev/null 2>&1 || [[ "$FORM_FACTOR" == wsl ]]; then
    exit 0
fi

install -Dm644 99-powercap-readable.rules /etc/udev/rules.d/99-powercap-readable.rules
udevadm control --reload-rules
udevadm trigger --action=add --subsystem-match=powercap
