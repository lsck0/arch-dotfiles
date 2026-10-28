#!/usr/bin/env -S nu --no-config-file
# per-monitor brightness in percent keyed by hyprland output name: the laptop backlight, else ddc

# "<connector>\t<bus>" lines, also read by hyprland/screen-dim.nu; per boot, i2c bus numbers are not stable
def bus-map-file []: nothing -> path { $env.XDG_RUNTIME_DIR? | default /tmp | path join ddcutil-bus-map.tsv }
# one lock for every ddcutil access to the i2c bus, shared with media-key.nu and screen-dim.nu: ddcutil's own i2c flock
# fails with no wait, so concurrent brightness set/get/dim across those three would make the DDC write fail
def ddc-lock []: nothing -> path { $env.XDG_RUNTIME_DIR? | default /tmp | path join ddc-i2c.lock }
const SLEEP_MULTIPLIER = "0.2"
const VCP_BRIGHTNESS = "10"
const PERCENT_MAX = 100
# VCP 0x10 maximum when ddcutil cannot report one: most monitors use 100, so percent maps straight to raw
const VCP_MAX_DEFAULT = 100

# getvcp --brief prints "VCP 10 C <cur> <max>"; the raw VCP maximum for a bus, VCP_MAX_DEFAULT when it cannot be read
def vcp-max [bus: string]: nothing -> int {
    let got = ^flock (ddc-lock) ddcutil --bus $bus --sleep-multiplier $SLEEP_MULTIPLIER getvcp $VCP_BRIGHTNESS --brief e> /dev/null | complete
    if $got.exit_code != 0 { return $VCP_MAX_DEFAULT }
    let max = $got.stdout | split row " " | get 4? | default "" | str trim
    if ($max | is-empty) { $VCP_MAX_DEFAULT } else { $max | into int }
}

def bus-map-refresh []: nothing -> table {
    let map = ^ddcutil detect --brief e> /dev/null | complete | get stdout
        | parse -r 'I2C bus:\s+\S*i2c-(?<bus>\d+)\s+DRM connector:\s+card\d+-(?<connector>\S+)'
        | select connector bus
    let file = bus-map-file
    mkdir ($file | path dirname)
    $map | to tsv --noheaders | save -f $"($file).new"
    mv -f $"($file).new" $file
    $map
}

def bus-find [connector: string]: nothing -> any {
    let cached = if (bus-map-file | path exists) {
        open --raw (bus-map-file) | lines | split column "\t" connector bus
    } else { [] }
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
    let read = {|bus| ^flock (ddc-lock) ddcutil --bus $bus --sleep-multiplier $SLEEP_MULTIPLIER getvcp $VCP_BRIGHTNESS --brief e> /dev/null | complete }
    let bus = bus-find $connector
    if $bus == null { exit 1 }
    mut vcp = do $read $bus
    if $vcp.exit_code != 0 {
        let fresh = bus-map-refresh | where connector == $connector | get 0?.bus
        if $fresh == null { exit 1 }
        $vcp = do $read $fresh
        if $vcp.exit_code != 0 { exit 1 }
    }
    let fields = $vcp.stdout | split row " "
    let cur = $fields | get 3 | str trim | into int
    let max = $fields | get 4? | default "" | str trim
    let max = if ($max | is-empty) { $VCP_MAX_DEFAULT } else { $max | into int }
    print (if $max > 0 { $cur * $PERCENT_MAX // $max } else { 0 })
}

def "main set" [connector: string, percent: int] {
    let percent = [0 ([$percent 100] | math min)] | math max
    if (backlight $connector) {
        ^brightnessctl -q -c backlight set $"($percent)%" o+e> /dev/null
        return
    }
    let bus = bus-find $connector
    if $bus == null { exit 1 }
    let raw = $percent * (vcp-max $bus) // $PERCENT_MAX
    ^flock (ddc-lock) ddcutil --bus $bus --noverify --sleep-multiplier $SLEEP_MULTIPLIER setvcp $VCP_BRIGHTNESS $raw o+e> /dev/null
}

def "main refresh" [] {
    bus-map-refresh | ignore
}
