#!/usr/bin/env -S nu --no-config-file
# idle dim and restore of the backlight and ddc/ci monitors, the pre-dim level per device saved for resume

const DDC_LOW = 10
const BACKLIGHT_LOW_PCT = 10
const VCP_BRIGHTNESS = "10"
const SELF = path self

def state-file []: nothing -> path { $env.XDG_RUNTIME_DIR | path join screen-dim }

def backlight []: nothing -> bool { glob /sys/class/backlight/* | is-not-empty }

def buses []: nothing -> list<string> {
    let mapped = try { open --raw ($env.XDG_RUNTIME_DIR? | default /tmp | path join ddcutil-bus-map.tsv) | lines | each { split row "\t" | get 1 } } catch { [] }
    if ($mapped | is-not-empty) { return $mapped }
    ^ddcutil detect --terse | complete | get stdout | parse --regex '/dev/i2c-(?<bus>\d+)' | get bus
}

# State file: a `backlight` line, then `<bus> <level>` per ddc/ci monitor.
def dim []: nothing -> nothing {
    if (state-file | path exists) { return }
    let panel = if (backlight) {
        let current = ^brightnessctl -m --class=backlight | complete | get stdout | lines | get 0? | default "" | split row "," | get 3?
            | default "" | str trim --right --char "%"
        if $current =~ '^\d+$' and ($current | into int) > $BACKLIGHT_LOW_PCT {
            ^brightnessctl --class=backlight -s set $"($BACKLIGHT_LOW_PCT)%" | ignore
            ["backlight"]
        } else { [] }
    } else { [] }
    let monitors = if (which ddcutil | is-empty) { [] } else {
        buses | par-each {|bus|
            let current = ^ddcutil --bus $bus getvcp $VCP_BRIGHTNESS --terse | complete | get stdout | split row " " | get --optional 3
            if $current == null or $current !~ '^\d+$' or ($current | into int) <= $DDC_LOW { return null }
            ^ddcutil --bus $bus setvcp $VCP_BRIGHTNESS ($DDC_LOW | into string) --noverify | complete | ignore
            $"($bus) ($current)"
        } | compact
    }
    $panel ++ $monitors | str join "\n" | save --force $"(state-file).new"
    mv --force $"(state-file).new" (state-file)
}

def restore []: nothing -> nothing {
    if not (state-file | path exists) { return }
    let lines = open --raw (state-file) | lines
    if "backlight" in $lines { ^brightnessctl -r | ignore }
    $lines | where $it =~ '^\d+ \d+$' | par-each {|line|
        let saved = $line | split row " "
        ^ddcutil --bus $saved.0 setvcp $VCP_BRIGHTNESS $saved.1 --noverify | complete | ignore
    } | ignore
    rm --force (state-file)
}

# one run at a time: a resume during the slow ddc dim waits, so restore never reads a half-written state
def main [action: string] {
    if $action not-in [dim restore] {
        print -e "usage: screen-dim.nu {dim|restore}"
        exit 1
    }
    ^flock $"(state-file).lock" nu --no-config-file $SELF $"locked-($action)"
}

def "main locked-dim" [] { dim }
def "main locked-restore" [] { restore }
