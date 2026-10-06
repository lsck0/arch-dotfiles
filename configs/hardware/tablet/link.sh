#!/usr/bin/env bash
# install the T1161 tablet support: udev rules that keep the kernel's nodes out of libinput's way, plus the userspace driver (see tablet-driver.py for why it exists)
cd "$(dirname "$(readlink -f "$0")")" || exit 1

source $DOTFILES/scripts/lib/platform.sh
# udevadm comes with systemd everywhere, wsl included, where windows owns the hardware
if ! command -v udevadm >/dev/null 2>&1 || [[ "$(platform_form_factor "$DOTFILES")" == wsl ]]; then
    exit 0
fi

set -e

# python-evdev is what the driver builds its virtual tablet with.
if ! python3 -c 'import evdev' >/dev/null 2>&1; then
    echo "tablet: python-evdev is missing, install it with: pacman -S python-evdev" >&2
fi

# root runs all three, so root-owned copies; 71- puts the uaccess tag in place before 73-seat-late.rules runs the builtin
sudo rm -f /etc/udev/rules.d/99-graphics-tablet.rules
sudo install -Dm644 71-graphics-tablet.rules /etc/udev/rules.d/71-graphics-tablet.rules
sudo install -Dm755 tablet-driver.py /usr/local/bin/tablet-driver
sudo install -Dm644 tablet-driver.service /etc/systemd/system/tablet-driver.service

sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input --subsystem-match=hidraw

# the udev rule only starts the driver on an add event, so a tablet already plugged in needs a nudge
if [ -n "$(find /sys/bus/usb/devices -maxdepth 2 -name idProduct \
            -exec grep -l '^6811$' {} + 2>/dev/null)" ]; then
    sudo systemctl restart tablet-driver.service
fi
