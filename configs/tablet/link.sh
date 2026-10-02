#!/usr/bin/env bash
#
# Installs the T1161 graphics tablet support: the udev rules that keep the
# kernel's own nodes out of libinput's way, and the userspace driver that
# actually makes the pad usable. See tablet-driver.py for why the driver has
# to exist at all.
cd "$(dirname "$(readlink -f "$0")")" || exit 1

if ! command -v udevadm >/dev/null 2>&1; then
    exit 0
fi

set -e

# python-evdev is what the driver builds its virtual tablet with.
if ! python3 -c 'import evdev' >/dev/null 2>&1; then
    echo "tablet: python-evdev is missing, install it with: pacman -S python-evdev" >&2
fi

# Symlinked rather than copied, so editing the checkout is enough. 71-, so the
# uaccess tag is in place before 73-seat-late.rules runs the builtin.
sudo rm -f /etc/udev/rules.d/99-graphics-tablet.rules
sudo ln -sfn "${PWD}/71-graphics-tablet.rules" /etc/udev/rules.d/71-graphics-tablet.rules

# The service runs with ProtectHome=read-only so this symlink resolves.
sudo ln -sfn "${PWD}/tablet-driver.py" /usr/local/bin/tablet-driver
sudo ln -sfn "${PWD}/tablet-driver.service" /etc/systemd/system/tablet-driver.service

sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input --subsystem-match=hidraw

# The udev rule only starts the driver on an add event, so a tablet that was
# already plugged in when the rules were installed needs a nudge.
if [ -n "$(find /sys/bus/usb/devices -maxdepth 2 -name idProduct \
            -exec grep -l '^6811$' {} + 2>/dev/null)" ]; then
    sudo systemctl restart tablet-driver.service || true
fi
