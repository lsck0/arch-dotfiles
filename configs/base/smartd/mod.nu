use module.nu *

export const meta = {packages: {native: [smartmontools]}, volatile: true}

export def system [cfg: record] {
    if (which smartd | is-empty) { return [] }
    if (^smartctl --scan | str trim | is-empty) { return (unit-disable smartd.service --now) }
    [
        (unit-enable smartd.service --now)
        (file-copy smartd.conf /etc/smartd.conf --then [systemctl restart smartd.service])
    ]
}
