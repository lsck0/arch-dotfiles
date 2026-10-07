#!/usr/bin/env bash
# card and fido access for every admin, whether or not anyone enrolled a key yet

HIDRAW_RULE=/etc/udev/rules.d/70-yubikey-hidraw.rules

install -Dm644 pcsc.rules /etc/polkit-1/rules.d/50-pcsc-wheel.rules
# retrigger only on a change, a replug otherwise applies it
if file_update 70-yubikey-hidraw.rules "$HIDRAW_RULE"; then
    udevadm control --reload
    udevadm trigger --action=change --subsystem-match=hidraw
fi
systemctl enable --now pcscd.socket
