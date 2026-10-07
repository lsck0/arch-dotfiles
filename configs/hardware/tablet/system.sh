#!/usr/bin/env bash
# install the T1161 tablet support: udev rules that keep the kernel's nodes out of libinput's way, plus the userspace driver (see tablet-driver.py for why it exists)

# usb id of the T1161, the udev rule starts the driver for it
TABLET_PRODUCT_ID=6811

# udevadm comes with systemd everywhere, wsl included, where windows owns the hardware
if ! command -v udevadm >/dev/null 2>&1 || [[ "$FORM_FACTOR" == wsl ]]; then
    exit 0
fi

# python-evdev is what the driver builds its virtual tablet with.
if ! python3 -c 'import evdev' >/dev/null 2>&1; then
    echo "tablet: python-evdev is missing, install it with: pacman -S python-evdev" >&2
fi

# root runs all three, so root-owned copies; 71- puts the uaccess tag in place before 73-seat-late.rules runs the builtin
install -Dm644 71-graphics-tablet.rules /etc/udev/rules.d/71-graphics-tablet.rules
install -Dm755 tablet-driver.py /usr/local/bin/tablet-driver
unit_install tablet-driver.service

udevadm control --reload-rules
udevadm trigger --subsystem-match=input --subsystem-match=hidraw

# the udev rule only starts the driver on an add event, so a tablet already plugged in needs a nudge
if [[ -n "$(find /sys/bus/usb/devices -maxdepth 2 -name idProduct -exec grep -l "^$TABLET_PRODUCT_ID\$" {} + 2>/dev/null)" ]]; then
    systemctl restart tablet-driver.service
fi
