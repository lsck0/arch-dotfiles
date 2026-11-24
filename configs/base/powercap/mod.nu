use module.nu *

export const meta = {native_only: [system]}

export def system [cfg: record] {
    let restart = unit-restart powercap-watts.service
    [
        (file-copy scripts/powercap-watts.sh /usr/local/bin/powercap-watts --mode 755 --then $restart)
        (unit-file services/powercap-watts.service --enable --now --then $restart)
        # intel_rapl_msr can load after multi-user.target starts the unit, whose condition then skips it: its device
        # pulls the unit in once it appears
        (udev-rules config/99-powercap-watts.rules)
    ]
}
