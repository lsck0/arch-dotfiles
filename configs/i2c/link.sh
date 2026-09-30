#!/usr/bin/env bash
# identical monitors without edid serial confuse powerdevil, so use ddc directly

if ! command -v ddcutil >/dev/null 2>&1; then
    exit 0
fi

set -e

# load i2c-dev at boot so /dev/i2c-* exists before the session starts
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
sudo modprobe i2c-dev || true

# ddcutil ships this udev rule; grant the i2c group access to the buses
sudo cp -f /usr/share/ddcutil/data/60-ddcutil-i2c.rules \
    /etc/udev/rules.d/60-ddcutil-i2c.rules 2>/dev/null || true

getent group i2c >/dev/null || sudo groupadd i2c
id -nG "$USER" | tr ' ' '\n' | grep -qx i2c || sudo gpasswd -a "$USER" i2c

sudo udevadm control --reload-rules || true
sudo udevadm trigger --subsystem-match=i2c-dev || true
