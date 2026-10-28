use module.nu *

export const meta = {packages: {native: [python-evdev]}}

const VENDOR_ID = "08f2"
const PRODUCT_ID = "6811"

export def system [cfg: record] {
    if (which udevadm | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    let plugged = glob /sys/bus/usb/devices/*/idProduct | any {|product_file|
        let dir = $product_file | path dirname
        let vendor = try { open --raw ($dir | path join idVendor) | str trim } catch { "" }
        (open --raw $product_file | str trim) == $PRODUCT_ID and $vendor == $VENDOR_ID
    }
    # a tablet already plugged in gets no add event
    let nudge = if $plugged { " && systemctl restart tablet-driver.service" } else { "" }
    let trigger = "udevadm trigger --subsystem-match=input --subsystem-match=hidraw"
    let restart = [sh -c $"udevadm control --reload-rules && ($trigger)($nudge)"]
    [
        # ahead of what restarts it: the udev nudge starts the unit, which runs this driver
        (unit-file tablet-driver.service)
        (file-copy tablet-driver.py /usr/local/bin/tablet-driver --mode 755 --then $restart)
        # 71- puts the uaccess tag in place before 73-seat-late.rules runs the builtin
        (file-copy 71-graphics-tablet.rules /etc/udev/rules.d/71-graphics-tablet.rules --then $restart)
    ]
}
