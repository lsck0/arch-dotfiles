use module.nu *

export const meta = {volatile: true}

const VALIDITY_UNITS = [python3-validity.service open-fprintd-resume.service open-fprintd-suspend.service]

# lsusb -d filters: the sensors python-validity supports; other Validity ids are libfprint's own.
const VALIDITY_USB_FILTERS = [138a:0090 138a:0097 138a:009d 06cb:009a]

# The vendor:product ids of the python-validity sensors present; without one its fprintd mask leaves a real sensor
# without a driver.
export def validity-sensor-ids []: nothing -> list<string> {
    $VALIDITY_USB_FILTERS | each {|filter| ^lsusb -d $filter | complete | get stdout | lines }
    | flatten | parse --regex 'ID (?<id>[0-9a-f]{4}:[0-9a-f]{4})' | get id | uniq
}

export def system [cfg: record] {
    let validity = ^systemctl list-unit-files --no-legend python3-validity.service | complete | get stdout | str trim
    if ($validity | is-empty) { return [] }
    if (validity-sensor-ids | is-empty) {
        let unmask = exec "unmask fprintd" [systemctl unmask fprintd.service]
        return ($VALIDITY_UNITS | each { unit-disable $in --now } | append $unmask)
    }
    [
        (dropin python3-validity.service override.conf --then [systemctl try-restart python3-validity.service])
        (dropin open-fprintd-resume.service open-fprintd-resume.conf)
        ...($VALIDITY_UNITS | each { unit-enable $in })
        (unit-mask fprintd.service --now)
    ]
}
