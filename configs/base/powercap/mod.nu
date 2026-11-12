use module.nu *

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let restart = unit-restart powercap-watts.service
    [
        (file-copy powercap-watts.sh /usr/local/bin/powercap-watts --mode 755 --then $restart)
        (unit-file powercap-watts.service --enable --now --then $restart)
        # intel_rapl_msr can load after multi-user.target starts the unit, whose condition then skips it: its device
        # pulls the unit in once it appears
        (file-copy 99-powercap-watts.rules /etc/udev/rules.d/99-powercap-watts.rules --then [udevadm control --reload-rules])
    ]
}
