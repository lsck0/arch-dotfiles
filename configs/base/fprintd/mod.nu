use module.nu *

export const meta = {volatile: true}

const VALIDITY_UNITS = [python3-validity.service open-fprintd-resume.service open-fprintd-suspend.service]

# Whether a python-validity sensor is present; elsewhere its fprintd mask leaves a real sensor without a driver.
export def validity-sensor []: nothing -> bool {
    [138a: 06cb:009a] | any {|id| (^lsusb -d $id | complete).exit_code == 0 }
}

export def system [cfg: record] {
    let validity = ^systemctl list-unit-files --no-legend python3-validity.service | complete | get stdout | str trim
    if ($validity | is-empty) { return [] }
    if not (validity-sensor) {
        let unmask = exec "unmask fprintd" [systemctl unmask fprintd.service]
        return ($VALIDITY_UNITS | each { unit-disable $in --now } | append $unmask)
    }
    [
        (dropin python3-validity.service override.conf --then [sh -c "systemctl daemon-reload && systemctl try-restart python3-validity.service"])
        (dropin open-fprintd-resume.service open-fprintd-resume.conf)
        ...($VALIDITY_UNITS | each { unit-enable $in })
        (unit-mask fprintd.service)
    ]
}
