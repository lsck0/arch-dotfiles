use module.nu *
use ../fprintd/mod.nu [validity-sensor-ids]

export const meta = {packages: {native: [tlp]}, volatile: true, native_only: [system]}

const PLATFORM_PROFILES = [performance balanced low-power]

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
    battery_max_perf_percent: {
        type: int
        default: 90
        doc: "CPU performance cap on battery, percent of the maximum (laptops)"
        label: "Battery CPU cap (%)"
        min: 10
        max: 100
    }
    platform_profile_ac: {
        type: string
        default: balanced
        choices: $PLATFORM_PROFILES
        doc: "Firmware platform profile on AC (laptops that have one)"
        label: "Platform profile on AC"
    }
    platform_profile_battery: {
        type: string
        default: low-power
        choices: $PLATFORM_PROFILES
        doc: "Firmware platform profile on battery (laptops that have one)"
        label: "Platform profile on battery"
    }
    energy_perf_policy: {
        type: string
        default: performance
        choices: [performance balance_performance default balance_power power]
        doc: "CPU energy/performance policy of a machine without a battery"
        label: "CPU energy policy (AC only)"
    }
    usb_autosuspend: {
        type: bool
        default: true
        doc: "Let TLP suspend idle USB devices; off for NICs, DACs, hubs or dongles that drop out and do not resume"
        label: "USB autosuspend"
    }
}

# read before /etc/tlp.conf, which wins: the keys set here stay out of the two tlp confs
const DROPINS = "/etc/tlp.d"

export def system [cfg: record] {
    if $cfg.charge_start >= $cfg.charge_stop { error make {msg: "tlp: charge_start must be below charge_stop"} }
    let restart = unit-restart tlp.service
    let conf = if $env.FORM_FACTOR? == "laptop" {
        let values = {
            START: $cfg.charge_start, STOP: $cfg.charge_stop, USB_DENYLIST: (validity-sensor-ids | str join ' ')
            MAX_PERF_ON_BAT: $cfg.battery_max_perf_percent, PROFILE_ON_AC: $cfg.platform_profile_ac
            PROFILE_ON_BAT: $cfg.platform_profile_battery
        }
        file-render config/bat.tlp.conf /etc/tlp.conf $values --then $restart
    } else {
        file-render config/ac-only.tlp.conf /etc/tlp.conf {ENERGY_PERF_POLICY: $cfg.energy_perf_policy} --then $restart
    }
    # bat.tlp.conf sets BAT0; any other battery (a second one, or a laptop whose only one is BAT1) gets the same
    let batteries = if $env.FORM_FACTOR? == "laptop" {
        glob /sys/class/power_supply/BAT* | path basename | where $it != BAT0 | sort
    } else { [] }
    let thresholds = $batteries | each {|b| $"START_CHARGE_THRESH_($b)=($cfg.charge_start)\nSTOP_CHARGE_THRESH_($b)=($cfg.charge_stop)\n" }
    [
        (unit-enable tlp.service --now)
        $conf
        (if not $cfg.usb_autosuspend { file-text $"($DROPINS)/10-usb.conf" "USB_AUTOSUSPEND=0\n" --then $restart })
        (if ($thresholds | is-not-empty) { file-text $"($DROPINS)/20-batteries.conf" ($thresholds | str join) --then $restart })
    ]
}
