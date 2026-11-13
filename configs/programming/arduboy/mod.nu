use module.nu *

export const meta = {packages: {pacman: [avrdude]}}

# Seat access to Arduboy FX boards over their USB serial port, without the uucp group and its re-login.
export def system [cfg: record] {
    # a board already plugged in gets no add event; the tty carries the vendor only as usb_id's property, not an attribute
    let reload = (udev-reload --action=change --property-match=ID_VENDOR_ID=2341
        --and "udevadm trigger --action=change --property-match=ID_VENDOR_ID=1b4f")
    udev-rules 71-arduboy.rules --then $reload
}
