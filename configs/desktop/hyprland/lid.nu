#!/usr/bin/env -S nu --no-config-file

# Docked lid closed: internal panel off so workspace 1 and the bar move to a visible screen.

const INTERNAL_PANEL = '^(eDP|LVDS|DSI)-'
const HEADLESS = '^HEADLESS-'
const LAYOUT = path self ../../../scripts/toggles/toggle-monitor-scale.nu
const SELF = path self

def lid-closed []: nothing -> bool {
    glob /proc/acpi/button/lid/*/state | any { open --raw $in | str contains "closed" }
}

def main [state?: string] {
    # a quick close and reopen starts two runs: one at a time, each reading the lid as it is now
    if $env.LID_LOCKED? == null {
        let lock = $env.XDG_RUNTIME_DIR? | default "/tmp" | path join lid.lock
        with-env {LID_LOCKED: "1"} { ^flock $lock nu --no-config-file $SELF ...([$state] | compact) }
        return
    }
    let proc = glob /proc/acpi/button/lid/*/state
    let closed = if ($proc | is-not-empty) { lid-closed } else { $state == "closed" }
    let monitors = ^hyprctl -j monitors all | from json | where name !~ $HEADLESS
    let internal = $monitors | where name =~ $INTERNAL_PANEL
    let external = $monitors | where name !~ $INTERNAL_PANEL and not $it.disabled
    for panel in $internal {
        if $closed and ($external | is-not-empty) and not $panel.disabled {
            ^nu --no-config-file ($LAYOUT | path expand) layout $panel.name off
        } else if not $closed and $panel.disabled {
            ^nu --no-config-file ($LAYOUT | path expand) layout $panel.name extend
        }
    }
}
