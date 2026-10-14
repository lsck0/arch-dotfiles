use module.nu *

# ddc monitor control: identical monitors without an edid serial confuse powerdevil, so ddc directly
export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let load = "modprobe i2c-dev && udevadm trigger --subsystem-match=i2c-dev"
    file-text /etc/modules-load.d/i2c-dev.conf "i2c-dev\n" --then [sh -c $load]
}
