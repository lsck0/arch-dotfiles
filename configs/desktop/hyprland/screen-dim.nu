#!/usr/bin/env -S nu --no-config-file
# idle dim and restore: laptop backlight via brightnessctl, external ddc/ci monitors via ddcutil; the pre-dim level per
# device is saved so resume brings it back

const DDC_LOW = 10
# a percentage: a raw 10 is near black on a panel with a high max
const BACKLIGHT_LOW = "10%"
const DDC_BUS_MAP = ".cache/ddcutil-bus-map.tsv"
const VCP_BRIGHTNESS = "10"
const SELF = path self

def state-file []: nothing -> path { $env.XDG_RUNTIME_DIR | path join screen-dim }

def backlight []: nothing -> bool { glob /sys/class/backlight/* | is-not-empty }

def buses []: nothing -> list<string> {
    # the bus map from monitor-brightness.nu skips a slow detect
    let mapped = try { open --raw ($nu.home-dir | path join $DDC_BUS_MAP) | lines | each { split row "\t" | get 1 } } catch { [] }
    if ($mapped | is-not-empty) { return $mapped }
    ^ddcutil detect --terse | complete | get stdout | parse --regex '/dev/i2c-(?<bus>\d+)' | get bus
}

def dim []: nothing -> nothing {
    # already dimmed: do not overwrite the saved baseline with the dimmed level
    if (state-file | path exists) { return }
    if (backlight) {
        ^brightnessctl -s set $BACKLIGHT_LOW | ignore
        "" | save (state-file)
        return
    }
    # ddc is slow, so one job per monitor; the state only exists once every baseline is in it
    let saved = buses | par-each {|bus|
        let current = ^ddcutil --bus $bus getvcp $VCP_BRIGHTNESS --terse | complete | get stdout | split row " " | get --optional 3
        if $current == null or $current !~ '^\d+$' { return null }
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

# one run at a time: a resume during the slow ddc dim waits for it, so restore never reads a half-written state or
# races jobs that would dim again after it
def main [action: string] {
    if $action not-in [dim restore] {
        print -e "usage: screen-dim.nu {dim|restore}"
        exit 1
    }
    ^flock $"(state-file).lock" nu --no-config-file $SELF $"locked-($action)"
}

def "main locked-dim" [] { dim }
def "main locked-restore" [] { restore }
