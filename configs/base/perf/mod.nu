use module.nu *

# i/o schedulers by device class; the cpu side is tlp's epp (base/tlp)
export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let reload = "udevadm control --reload; udevadm trigger --subsystem-match=block; true"
    file-copy 60-ioschedulers.rules /etc/udev/rules.d/60-ioschedulers.rules --then [sh -c $reload]
}
