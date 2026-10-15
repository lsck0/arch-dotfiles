use module.nu *

export const meta = {packages: {native: [python-evdev]}}

# the T1161's usb product id; its udev rule starts the driver on an add event
const PRODUCT_ID = "6811"

# udev rules that keep the kernel's nodes from libinput, plus the userspace driver (tablet-driver.py says why)
export def system [cfg: record] {
    # wsl has udevadm too, but windows owns the hardware
    if (which udevadm | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    let plugged = glob /sys/bus/usb/devices/*/idProduct | any { (open --raw $in | str trim) == $PRODUCT_ID }
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
