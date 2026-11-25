#!/usr/bin/env -S nu --no-config-file
# idle dim and restore of the backlight, the keyboard light and ddc/ci monitors, the pre-dim level per device saved for
# resume; the save outlives a crash or power loss, and each login restores what it still holds (hyprland_autostart.lua),
# since a dimmed monitor keeps the low level in its own firmware

const DDC_LOW = 10
const BACKLIGHT_LOW_PCT = 10
const VCP_BRIGHTNESS = "10"
const BACKLIGHT_LINE = "backlight"
const KBD_LINE = "kbd"
const DDC_LINE = "ddc"
const SELF = path self

def runtime-dir []: nothing -> path { $env.XDG_RUNTIME_DIR? | default /tmp }

def state-file []: nothing -> path {
    $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join screen-dim
}

# `ddc <connector> <level>` lines a restore could not set (the monitor unplugged, asleep or not answering): each later
# restore tries them again, so a monitor never keeps the dim level in its firmware for good
def pending-file []: nothing -> path { $"(state-file)-pending" }

def backlight []: nothing -> bool { glob /sys/class/backlight/* | is-not-empty }

# connector and bus of each ddc/ci monitor; the bus is only valid this boot, so the state keys a monitor by connector.
# Runs under the ddc lock (main), so it reads ddcutil itself and never the locking monitor-brightness.nu. The cached
# map is stale when it lacks a wanted connector: ddcutil detect then looks again.
def monitors [wanted: list<string> = []]: nothing -> table<connector: string, bus: string> {
    let mapped = try {
        open --raw (runtime-dir | path join ddcutil-bus-map.tsv) | lines | split column "\t" connector bus
    } catch { [] }
    if ($mapped | is-not-empty) and ($wanted | all { $in in $mapped.connector }) { return $mapped }
    ^ddcutil detect --terse | complete | get stdout
    | parse --regex 'I2C bus:\s+\S*i2c-(?<bus>\d+)\s+DRM connector:\s+card\d+-(?<connector>\S+)'
    | select connector bus
}

def kbd-lights []: nothing -> list<string> { glob /sys/class/leds/*kbd_backlight* | path basename }

# State file: `backlight <level>` for the panel, `kbd <device> <level>` per lit keyboard light, then
# `ddc <connector> <level>` per ddc/ci monitor; raw levels, so a restore after a reboot needs nothing saved elsewhere
def dim [ddc: bool]: nothing -> nothing {
    if (state-file | path exists) { return }
    let panel = if (backlight) {
        let fields = ^brightnessctl -m --class=backlight | complete | get stdout | lines | get --optional 0 | default "" | split row ","
        let level = $fields | get --optional 2 | default ""
        let percent = $fields | get --optional 3 | default "" | str trim --right --char "%"
        if $level =~ '^\d+$' and $percent =~ '^\d+$' and ($percent | into int) > $BACKLIGHT_LOW_PCT {
            ^brightnessctl --quiet --class=backlight set $"($BACKLIGHT_LOW_PCT)%" | complete | ignore
            [$"($BACKLIGHT_LINE) ($level)"]
        } else { [] }
    } else { [] }
    let keyboards = kbd-lights | each {|device|
        let current = ^brightnessctl --device $device get | complete | get stdout | str trim
        if $current !~ '^[1-9]\d*$' { return null }
        ^brightnessctl --quiet --device $device set 0 | complete | ignore
        $"($KBD_LINE) ($device) ($current)"
    } | compact
    let ddc_levels = if not $ddc or (which ddcutil | is-empty) { [] } else {
        monitors | par-each {|monitor|
            let current = ^ddcutil --bus $monitor.bus getvcp $VCP_BRIGHTNESS --terse | complete | get stdout | split row " " | get --optional 3
            if $current == null or $current !~ '^\d+$' or ($current | into int) <= $DDC_LOW { return null }
            ^ddcutil --bus $monitor.bus setvcp $VCP_BRIGHTNESS ($DDC_LOW | into string) --noverify | complete | ignore
            $"($DDC_LINE) ($monitor.connector) ($current)"
        } | compact
    }
    mkdir (state-file | path dirname)
    $panel ++ $keyboards ++ $ddc_levels | str join "\n" | save --force $"(state-file).new"
    mv --force $"(state-file).new" (state-file)
}

def restore []: nothing -> nothing {
    if not (state-file | path exists) and not (pending-file | path exists) { return }
    let lines = if (state-file | path exists) { open --raw (state-file) | lines } else { [] }
    for saved in ($lines | parse $"($BACKLIGHT_LINE) {level}") {
        ^brightnessctl --quiet --class=backlight set $saved.level | complete | ignore
    }
    for saved in ($lines | parse $"($KBD_LINE) {device} {level}") {
        ^brightnessctl --quiet --device $saved.device set $saved.level | complete | ignore
    }
    let pending = if (pending-file | path exists) { open --raw (pending-file) | lines } else { [] }
    # this dim's level wins over an older pending one of the same monitor
    let saved_monitors = $pending ++ $lines | parse $"($DDC_LINE) {connector} {level}" | reverse | uniq-by connector
    let unset = if ($saved_monitors | is-empty) or (which ddcutil | is-empty) { $saved_monitors } else {
        let buses = monitors $saved_monitors.connector
        $saved_monitors | par-each {|saved|
            let bus = $buses | where connector == $saved.connector | get --optional 0.bus
            if $bus != null and (^ddcutil --bus $bus setvcp $VCP_BRIGHTNESS $saved.level --noverify | complete).exit_code == 0 {
                return null
            }
            $saved
        } | compact
    }
    if ($unset | is-empty) {
        rm --force (pending-file)
    } else {
        $unset | each { $"($DDC_LINE) ($in.connector) ($in.level)" } | str join "\n" | save --force $"(pending-file).new"
        mv --force $"(pending-file).new" (pending-file)
    }
    rm --force (state-file)
}

# one run at a time: a resume during the slow ddc dim waits, so restore never reads a half-written state; --no-ddc
# leaves ddc/ci monitors alone (hyprland's idle_dim_monitors)
def main [action: string, --no-ddc] {
    if $action not-in [dim restore] { error make {msg: $"screen-dim: action is dim or restore, not ($action)"} }
    let verb = if $action == dim and $no_ddc { "locked-dim-panel" } else { $"locked-($action)" }
    ^flock (runtime-dir | path join ddc-i2c.lock) nu --no-config-file $SELF $verb
}

def "main locked-dim" [] { dim true }
def "main locked-dim-panel" [] { dim false }
def "main locked-restore" [] { restore }
