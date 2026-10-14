use module.nu *

export const meta = {packages: {native: [smartmontools]}, volatile: true}

# disk health; the unit skips itself in a vm
export def system [cfg: record] {
    if (which smartd | is-empty) { return [] }
    # no smart-capable disk (emmc): smartd would fail on every boot
    if (^smartctl --scan | str trim | is-empty) { return (unit-disable smartd.service --now) }
    [
        (unit-enable smartd.service --now)
        (file-copy smartd.conf /etc/smartd.conf --then [systemctl restart smartd.service])
    ]
}
