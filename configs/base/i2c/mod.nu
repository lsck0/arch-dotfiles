# ddc monitor control: identical monitors without an edid serial confuse powerdevil, so ddc goes over i2c-dev

use module.nu *

export const meta = {native_only: [system]}

export def system [cfg: record] {
    let load = "modprobe i2c-dev && udevadm trigger --subsystem-match=i2c-dev"
    file-text /etc/modules-load.d/i2c-dev.conf "i2c-dev\n" --then [sh -c $load]
}
