use module.nu *
use ../fprintd/mod.nu [validity-sensor-ids]

export const meta = {packages: {native: [tlp]}, volatile: true}

export const options = {
    charge_start: {
        type: int
        default: 95
        doc: "Battery charge level below which charging starts (laptops whose firmware supports thresholds)"
        min: 0
        max: 100
    }
    charge_stop: {
        type: int
        default: 100
        doc: "Battery charge level at which charging stops; 80 spares an always-plugged battery"
        min: 1
        max: 100
    }
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    if $cfg.charge_start >= $cfg.charge_stop { error make {msg: "tlp: charge_start must be below charge_stop"} }
    let restart = unit-restart tlp.service
    let conf = if $env.FORM_FACTOR? == "laptop" {
        let values = {START: $cfg.charge_start, STOP: $cfg.charge_stop, USB_DENYLIST: (validity-sensor-ids | str join ' ')}
        file-render bat.tlp.conf /etc/tlp.conf $values --then $restart
    } else {
        file-copy ac-only.tlp.conf /etc/tlp.conf --then $restart
    }
    [(unit-enable tlp.service --now) $conf]
}
