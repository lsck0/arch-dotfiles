use module.nu *

# Seat access to Espressif boards over their built-in USB JTAG/serial unit, without the uucp group and its re-login.
export def system [cfg: record] {
    # a board already plugged in gets no add event
    let reload = [sh -c "udevadm control --reload-rules && udevadm trigger --subsystem-match=tty --subsystem-match=usb --attr-match=idVendor=303a"]
    [(file-copy 71-espressif.rules /etc/udev/rules.d/71-espressif.rules --then $reload)]
}
