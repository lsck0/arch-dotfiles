#!/usr/bin/env bash
# identical monitors without edid serial confuse powerdevil, so use ddc directly

# load i2c-dev at boot so /dev/i2c-* exists before the session starts
echo "i2c-dev" | install -Dm644 /dev/stdin /etc/modules-load.d/i2c-dev.conf
modprobe i2c-dev
udevadm trigger --subsystem-match=i2c-dev
