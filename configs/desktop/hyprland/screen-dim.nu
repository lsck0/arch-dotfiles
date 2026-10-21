#!/usr/bin/env -S nu --no-config-file
# idle dim and restore of the backlight and ddc/ci monitors, the pre-dim level per device saved for resume

const DDC_LOW = 10
const BACKLIGHT_LOW_PCT = 10
const DDC_BUS_MAP = ".cache/ddcutil-bus-map.tsv"
const VCP_BRIGHTNESS = "10"
const SELF = path self

def state-file []: nothing -> path { $env.XDG_RUNTIME_DIR | path join screen-dim }

def backlight []: nothing -> bool { glob /sys/class/backlight/* | is-not-empty }

def buses []: nothing -> list<string> {
    let mapped = try { open --raw ($nu.home-dir | path join $DDC_BUS_MAP) | lines | each { split row "\t" | get 1 } } catch { [] }
    if ($mapped | is-not-empty) { return $mapped }
    ^ddcutil detect --terse | complete | get stdout | parse --regex '/dev/i2c-(?<bus>\d+)' | get bus
}

def dim []: nothing -> nothing {
    if (state-file | path exists) { return }
    if (backlight) {
        let current = ^brightnessctl -m --class=backlight | complete | get stdout | lines | get 0? | default "" | split row "," | get 3?
            | default "" | str trim --right --char "%"
        if $current !~ '^\d+$' or ($current | into int) <= $BACKLIGHT_LOW_PCT { return }
        ^brightnessctl --class=backlight -s set $"($BACKLIGHT_LOW_PCT)%" | ignore
        "" | save (state-file)
        return
    }
    let saved = buses | par-each {|bus|
        let current = ^ddcutil --bus $bus getvcp $VCP_BRIGHTNESS --terse | complete | get stdout | split row " " | get --optional 3
        if $current == null or $current !~ '^\d+$' or ($current | into int) <= $DDC_LOW { return null }
        ^ddcutil --bus $bus setvcp $VCP_BRIGHTNESS ($DDC_LOW | into string) --noverify | complete | ignore
        $"($bus) ($current)"
    } | compact
    $saved | str join "\n" | save --force $"(state-file).new"
    mv --force $"(state-file).new" (state-file)
}

def restore []: nothing -> nothing {
    if not (state-file | path exists) { return }
    if (backlight) {
        ^brightnessctl -r | ignore
    } else {
        open --raw (state-file) | lines | where $it =~ '^\d+ \d+$' | par-each {|line|
            let saved = $line | split row " "
            ^ddcutil --bus $saved.0 setvcp $VCP_BRIGHTNESS $saved.1 --noverify | complete | ignore
        } | ignore
    }
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
