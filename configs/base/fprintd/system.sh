#!/usr/bin/env bash

unit_present python3-validity.service || exit 0

# python-validity drives validity/synaptics sensors only (usb vendor 138a, 06cb:009a); everywhere else it crash-loops and its fprintd mask leaves a real sensor without a driver
if ! lsusb -d 138a: >/dev/null 2>&1 && ! lsusb -d 06cb:009a >/dev/null 2>&1; then
    systemctl disable --now python3-validity.service open-fprintd-resume.service open-fprintd-suspend.service 2>/dev/null || true
    rm -rf /etc/systemd/system/python3-validity.service.d
    systemctl unmask fprintd.service
    systemctl daemon-reload
    systemctl reset-failed python3-validity.service 2>/dev/null || true
    exit 0
fi

install -Dm644 python3-validity-override.conf /etc/systemd/system/python3-validity.service.d/override.conf
systemctl daemon-reload
systemctl enable python3-validity.service open-fprintd-resume.service open-fprintd-suspend.service
systemctl mask fprintd.service
