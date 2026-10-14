#!/usr/bin/env -S nu --no-config-file
# per-monitor brightness in percent keyed by hyprland output name: the laptop backlight, else ddc

# "<connector>\t<bus>" lines, also read by hyprland/screen-dim.nu to skip a slow detect
const BUS_MAP = "~/.cache/ddcutil-bus-map.tsv"
const SLEEP_MULTIPLIER = "0.2"
const VCP_BRIGHTNESS = "10"

def bus-map-refresh []: nothing -> table {
    let map = ^ddcutil detect --brief e> /dev/null | complete | get stdout
        | parse -r 'I2C bus:\s+\S*i2c-(?<bus>\d+)\s+DRM connector:\s+card\d+-(?<connector>\S+)'
        | select connector bus
    let file = $BUS_MAP | path expand
    mkdir ($file | path dirname)
    $map | to tsv --noheaders | save -f $"($file).new"
    mv -f $"($file).new" $file
    $map
}

def bus-find [connector: string]: nothing -> any {
    let cached = if ($BUS_MAP | path expand | path exists) {
        open --raw ($BUS_MAP | path expand) | lines | split column "\t" connector bus
    } else { [] }
    # a monitor plugged in after the map was built
    $cached | where connector == $connector | get 0?.bus
        | default { bus-map-refresh | where connector == $connector | get 0?.bus }
}

def backlight [connector: string]: nothing -> bool {
    ($connector | str starts-with eDP) and (glob /sys/class/backlight/* | is-not-empty)
}

def main [] {
    print -e (help main)
    exit 2
}

def "main get" [connector: string] {
    if (backlight $connector) {
        let max = ^brightnessctl -c backlight -m max | into int
        print (if $max > 0 { (^brightnessctl -c backlight -m get | into int) * 100 // $max } else { 0 })
        return
    }
    let bus = bus-find $connector
    if $bus == null { exit 1 }
    let vcp = ^ddcutil --bus $bus --sleep-multiplier $SLEEP_MULTIPLIER getvcp $VCP_BRIGHTNESS --brief e> /dev/null
    print ($vcp | split row " " | get 3)
}

def "main set" [connector: string, percent: int] {
    let percent = [0 ([$percent 100] | math min)] | math max
    if (backlight $connector) {
        ^brightnessctl -q -c backlight set $"($percent)%" o+e> /dev/null
        return
    }
    let bus = bus-find $connector
    if $bus == null { exit 1 }
    ^ddcutil --bus $bus --noverify --sleep-multiplier $SLEEP_MULTIPLIER setvcp $VCP_BRIGHTNESS $percent o+e> /dev/null
}

def "main refresh" [] {
    bus-map-refresh | ignore
}
