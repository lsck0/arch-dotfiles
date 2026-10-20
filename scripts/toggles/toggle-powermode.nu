#!/usr/bin/env -S nu --no-config-file
use lib.nu [notify root-run state-get state-set state-clear state-file quickshell-call cycle-next toggle-run]
use ../lib/platform.nu [platform-load]

const MODES = {
    balanced: {label: "Balanced"}
    performance: {label: "Performance"}
    power-saver: {label: "Power saver"}
}
const REPO = path self ../..
const GHOSTTY_TIMEOUT_S = 3

def current []: nothing -> any { state-get powermode --volatile | if $in in $MODES { $in } }

# a laptop off its battery per upower; a desktop on a ups never counts
def on-battery []: nothing -> bool {
    (platform-load $REPO).form_factor == laptop and (
        ^busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery | complete
    ).stdout == "b true\n"
}

# the one saver rule: forced power-saver, or auto on a laptop's battery; a forced balanced or performance wins
def saver []: nothing -> bool {
    match (current) { power-saver => true, null => (on-battery), _ => false }
}

# hyprland and quickshell read the volatile powersaver state themselves; the desktop reloads only when saver flips
def saver-sync []: nothing -> nothing {
    let saver = if (saver) { "on" } else { "off" }
    if (state-get powersaver --volatile) == $saver { return }
    state-set powersaver $saver --volatile
    let ghostty_conf = state-file ghostty-powersave.conf --volatile
    if $saver == on { "cursor-style-blink = false\n" | save --force $ghostty_conf } else { rm --force $ghostty_conf }
    # ghostty has no config watcher, reload-config is only reachable over d-bus
    (^timeout $GHOSTTY_TIMEOUT_S gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty
        --method org.gtk.Actions.Activate reload-config '[]' '{}' | complete)
    ^hyprctl reload config-only | complete
    # the reload drops the runtime-only shader and monitor layout
    toggle-run shader reapply | complete
    toggle-run monitor-scale reapply | complete
    quickshell-call shell reloadPowerMode | complete | ignore
}

def apply [mode: string]: nothing -> nothing {
    root-run tlp $mode
    state-set powermode $mode --volatile
    saver-sync
    notify "Power mode" ($MODES | get $mode | get label)
}

# empty means no forced mode
def "main get" [] { current | default "" }

def "main label" [] {
    match (current) {
        null => "○ Power: Auto"
        $mode => $"● Power: ($MODES | get $mode | get label)"
    }
}

# auto is a stop of its own: else the first press leaves it for good
def "main toggle" [] {
    let next = [auto] | append ($MODES | columns) | cycle-next (current | default auto)
    if $next == auto { auto } else { apply $next }
}
def "main performance" [] { apply performance }
def "main balanced" [] { apply balanced }
def "main power-saver" [] { apply power-saver }

# un-force: back to tlp's own ac/bat auto-detect, not a static profile
def auto []: nothing -> nothing {
    root-run tlp start
    state-clear powermode --volatile
    saver-sync
    notify "Power mode" "Auto"
}

def "main set" [mode: string] {
    if $mode == auto { return (auto) }
    if $mode not-in $MODES { error make {msg: $"power mode is one of auto, ($MODES | columns | str join ', ')"} }
    apply $mode
}

def "main auto" [] { auto }

def "main sync" [] { saver-sync }
def main [] { main toggle }
