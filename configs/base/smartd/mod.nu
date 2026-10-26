use module.nu *

export const meta = {packages: {native: [smartmontools]}, volatile: true}

export const options = {
    test_schedule: {
        type: string
        default: "S/../.././02|L/../../6/03"
        doc: "When smartd runs self-tests, smartd.conf(5) -s regex syntax (default: short test daily at 02:00, long test Saturday at 03:00)"
        label: "SMART test schedule"
    }
}

export def system [cfg: record] {
    if (which smartd | is-empty) { return [] }
    if (^smartctl --scan | str trim | is-empty) { return (unit-disable smartd.service --now) }
    [
        (unit-enable smartd.service --now)
        (file-render smartd.conf /etc/smartd.conf {TEST_SCHEDULE: $cfg.test_schedule} --then [systemctl restart smartd.service])
    ]
}
