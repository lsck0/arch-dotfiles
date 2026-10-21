use module.nu *

export const meta = {packages: {native: [tlp]}}

export const options = {
    charge_start: {
        type: int
        default: 95
        doc: "Battery charge level below which charging starts (laptops whose firmware supports thresholds)"
        label: "Charge start"
        min: 0
        max: 100
        scope: machine
    }
    charge_stop: {
        type: int
        default: 100
        doc: "Battery charge level at which charging stops; 80 spares an always-plugged battery"
        label: "Charge stop"
        min: 1
        max: 100
        scope: machine
    }
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    if $cfg.charge_start >= $cfg.charge_stop { error make {msg: "tlp: charge_start must be below charge_stop"} }
    let conf = if $env.FORM_FACTOR? == "laptop" {
        let thresholds = {START: $cfg.charge_start, STOP: $cfg.charge_stop}
        file-render bat.tlp.conf /etc/tlp.conf $thresholds --then [systemctl restart tlp.service]
    } else {
        file-copy ac-only.tlp.conf /etc/tlp.conf --then [systemctl restart tlp.service]
    }
    [(unit-enable tlp.service --now) $conf]
}
