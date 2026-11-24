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

# the VCP maximum is fixed per monitor, so it is read once per bus map and spares every set a DDC round trip;
# bus-map-refresh drops them all, so a monitor swapped onto the same port reads its own maximum
def vcp-max-file [connector: string, bus: string]: nothing -> path {
    $env.XDG_RUNTIME_DIR? | default /tmp | path join $"ddc-vcp-max.($connector).($bus)"
}

# atomic, as a concurrent set may read it while get rewrites it; best effort, a refresh may remove the temp file
def vcp-max-save [connector: string, bus: string, max: int] {
    let file = vcp-max-file $connector $bus
    try {
        $max | into string | save -f $"($file).($nu.pid)"
        mv -f $"($file).($nu.pid)" $file
    }
}

# getvcp --brief prints "VCP 10 C <cur> <max>"; VCP_MAX_DEFAULT when the monitor reports no maximum
def vcp-parse [stdout: string]: nothing -> record {
    let fields = $stdout | split row " "
    let max = $fields | get 4? | default "" | str trim
    {cur: ($fields | get 3 | str trim | into int), max: (if ($max | is-empty) { $VCP_MAX_DEFAULT } else { $max | into int })}
}

def vcp-max [connector: string, bus: string]: nothing -> int {
    let file = vcp-max-file $connector $bus
    let cached = try { open --raw $file | decode utf-8 | str trim | into int } catch { null }
    if $cached != null { return $cached }
    let got = ^flock (ddc-lock) ddcutil --bus $bus --sleep-multiplier $SLEEP_MULTIPLIER getvcp $VCP_BRIGHTNESS --brief e> /dev/null | complete
    if $got.exit_code != 0 { return $VCP_MAX_DEFAULT }
    let max = (vcp-parse $got.stdout).max
    vcp-max-save $connector $bus $max
    $max
}

def bus-map-refresh []: nothing -> table {
    let map = ^flock (ddc-lock) ddcutil detect --brief e> /dev/null | complete | get stdout
        | parse -r 'I2C bus:\s+\S*i2c-(?<bus>\d+)\s+DRM connector:\s+card\d+-(?<connector>\S+)'
        | select connector bus
    let file = bus-map-file
    mkdir ($file | path dirname)
    $map | to tsv --noheaders | save -f $"($file).new"
    mv -f $"($file).new" $file
    let stale = glob ($file | path dirname | path join "ddc-vcp-max.*")
    if ($stale | is-not-empty) { rm -f ...$stale }
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
    mut bus = bus-find $connector
    if $bus == null { exit 1 }
    mut vcp = do $read $bus
    if $vcp.exit_code != 0 {
        $bus = bus-map-refresh | where connector == $connector | get 0?.bus
        if $bus == null { exit 1 }
        $vcp = do $read $bus
        if $vcp.exit_code != 0 { exit 1 }
    }
    let got = vcp-parse $vcp.stdout
    vcp-max-save $connector $bus $got.max
    print (if $got.max > 0 { $got.cur * $PERCENT_MAX // $got.max } else { 0 })
}

def "main set" [connector: string, percent: int] {
    let percent = [0 ([$percent $PERCENT_MAX] | math min)] | math max
    if (backlight $connector) {
        ^brightnessctl -q -c backlight set $"($percent)%" o+e> /dev/null
        return
    }
    let bus = bus-find $connector
    if $bus == null { exit 1 }
    let raw = $percent * (vcp-max $connector $bus) // $PERCENT_MAX
    ^flock (ddc-lock) ddcutil --bus $bus --noverify --sleep-multiplier $SLEEP_MULTIPLIER setvcp $VCP_BRIGHTNESS $raw o+e> /dev/null
}

def "main refresh" [] {
    bus-map-refresh | ignore
}
