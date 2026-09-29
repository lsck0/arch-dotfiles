#!/usr/bin/env bash
# i2c/DDC brightness for external monitors. Two identical monitors with no EDID
# serial confuse powerdevil's display matching, so one stops taking brightness;
# giving the i2c group direct /dev/i2c access makes DDC control reliable.

if ! command -v ddcutil >/dev/null 2>&1; then
    exit 0
fi

set -ex

# load i2c-dev at boot so /dev/i2c-* exists before the session starts
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
sudo modprobe i2c-dev || true

# ddcutil ships this udev rule; grant the i2c group access to the buses
sudo cp -f /usr/share/ddcutil/data/60-ddcutil-i2c.rules \
    /etc/udev/rules.d/60-ddcutil-i2c.rules 2>/dev/null || true

# ensure the i2c group exists and the user is in it
getent group i2c >/dev/null || sudo groupadd i2c
id -nG "$USER" | tr ' ' '\n' | grep -qx i2c || sudo gpasswd -a "$USER" i2c

sudo udevadm control --reload-rules || true
sudo udevadm trigger --subsystem-match=i2c-dev || true
