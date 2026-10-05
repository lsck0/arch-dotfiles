#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source ../../scripts/lib/platform.sh
# udevadm comes with systemd everywhere, wsl included, where windows owns the hardware
if ! command -v udevadm >/dev/null 2>&1 || [[ "$(platform_form_factor ../..)" == wsl ]]; then
    exit 0
fi

set -e

sudo install -Dm644 99-powercap-readable.rules /etc/udev/rules.d/99-powercap-readable.rules

sudo udevadm control --reload-rules
sudo udevadm trigger --action=add --subsystem-match=powercap
