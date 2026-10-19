use module.nu *

export def system [cfg: record] {
    if (which udevadm | is-empty) or $env.FORM_FACTOR? == "wsl" { return [] }
    let reload = "udevadm control --reload-rules && udevadm trigger --action=add --subsystem-match=powercap"
    file-copy 99-powercap-readable.rules /etc/udev/rules.d/99-powercap-readable.rules --then [sh -c $reload]
}
