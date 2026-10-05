#!/usr/bin/env bash
# identical monitors without edid serial confuse powerdevil, so use ddc directly

if ! command -v ddcutil >/dev/null 2>&1; then
    exit 0
fi

set -e

# load i2c-dev at boot so /dev/i2c-* exists before the session starts
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
sudo modprobe i2c-dev

# ddcutil ships this udev rule; grant the i2c group access to the buses
sudo install -Dm644 /usr/share/ddcutil/data/60-ddcutil-i2c.rules /etc/udev/rules.d/60-ddcutil-i2c.rules

getent group i2c >/dev/null || sudo groupadd i2c
id -nG "$USER" | tr ' ' '\n' | grep -qx i2c || sudo gpasswd -a "$USER" i2c

sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=i2c-dev
