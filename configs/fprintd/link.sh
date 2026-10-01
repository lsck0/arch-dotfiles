#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! systemctl list-unit-files --no-legend python3-validity.service 2>/dev/null | grep -q .; then
    exit 0
fi

set -e

# python-validity drives validity/synaptics sensors only (usb vendor 138a, 06cb:009a); everywhere else it
# crash-loops and its fprintd mask leaves a real sensor without a driver
if ! lsusb -d 138a: >/dev/null 2>&1 && ! lsusb -d 06cb:009a >/dev/null 2>&1; then
    sudo systemctl disable --now python3-validity.service 2>/dev/null || true
    sudo rm -rf /etc/systemd/system/python3-validity.service.d
    sudo systemctl unmask fprintd.service
    sudo systemctl daemon-reload
    sudo systemctl reset-failed python3-validity.service 2>/dev/null || true
    exit 0
fi

sudo mkdir -p /etc/systemd/system/python3-validity.service.d
sudo ln -sfn "${PWD}/python3-validity-override.conf" /etc/systemd/system/python3-validity.service.d/override.conf
sudo systemctl daemon-reload
sudo systemctl enable python3-validity.service
sudo systemctl mask fprintd.service
