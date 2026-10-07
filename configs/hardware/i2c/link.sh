#!/usr/bin/env bash
# identical monitors without edid serial confuse powerdevil, so use ddc directly

set -e

# load i2c-dev at boot so /dev/i2c-* exists before the session starts
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
sudo modprobe i2c-dev

# an old run copied ddcutil's all-comments sample here, shadowing the packaged rule of the same name
sudo rm -f /etc/udev/rules.d/60-ddcutil-i2c.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=i2c-dev
