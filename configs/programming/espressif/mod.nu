use module.nu *

# Seat access to Espressif boards over their built-in USB JTAG/serial unit, without the uucp group and its re-login.
export def system [cfg: record] {
    # a board already plugged in gets no add event; the tty carries the vendor only as usb_id's property, not an attribute
    udev-rules 71-espressif.rules --action=change --property-match=ID_VENDOR_ID=303a --property-match=ID_MODEL_ID=1001
}
