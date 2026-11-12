#!/usr/bin/env -S nu --no-config-file
use lib.nu [status-record status-print notify root-run state-get state-set state-clear state-file quickshell-call cycle-next toggle-run]
use ../lib/platform.nu [platform-load]

# auto is no forced mode: tlp picks by the power source
const MODES = {auto: Auto, balanced: Balanced, performance: Performance, power-saver: "Power saver"}
const REPO = path self ../..
const GHOSTTY_TIMEOUT_S = 3

def current []: nothing -> string { state-get powermode --volatile | if $in in $MODES { $in } else { "auto" } }

def on-battery []: nothing -> bool {
    (platform-load $REPO).form_factor == laptop and (
        ^busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery | complete
    ).stdout == "b true\n"
}

# The one saver rule: forced power-saver, or auto on a laptop's battery; a forced balanced or performance wins.
def saver []: nothing -> bool {
    match (current) { power-saver => true, auto => (on-battery), _ => false }
}

# Reloads ghostty, hyprland, the shader, the monitor layout and the bar, only when the saver state flips.
def saver-sync []: nothing -> nothing {
    let saver = if (saver) { "on" } else { "off" }
    if (state-get powersaver --volatile) == $saver { return }
    state-set powersaver $saver --volatile
    let ghostty_conf = state-file ghostty-powersave.conf --volatile
    if $saver == on { "cursor-style-blink = false\n" | save --force $ghostty_conf } else { rm --force $ghostty_conf }
    (^timeout $GHOSTTY_TIMEOUT_S gdbus call --session --dest com.mitchellh.ghostty --object-path /com/mitchellh/ghostty
        --method org.gtk.Actions.Activate reload-config '[]' '{}' | complete)
    ^hyprctl reload config-only | complete
    toggle-run shader reapply | complete
    toggle-run monitor-scale reapply | complete
    quickshell-call shell reloadPowerMode | complete | ignore
}

def apply [mode: string]: nothing -> nothing {
    if $mode not-in $MODES { error make {msg: $"power mode is one of ($MODES | columns | str join ', ')"} }
    if $mode == auto {
        root-run tlp start
        state-clear powermode --volatile
    } else {
        root-run tlp $mode
        state-set powermode $mode --volatile
    }
    saver-sync
    notify "Power mode" ($MODES | get $mode)
}

# auto prints empty
def "main get" [--json] {
    let mode = current
    if not $json { return (if $mode == auto { "" } else { $mode }) }
    status-print (status-record "Power mode" $mode --text ($MODES | get $mode) --states ($MODES | columns)) true
}

# auto is a stop of its own: else the first press leaves it for good
def "main toggle" [] { apply ($MODES | columns | cycle-next (current)) }
def "main set" [mode: string] { apply $mode }
def "main auto" [] { apply auto }
def "main balanced" [] { apply balanced }
def "main performance" [] { apply performance }
def "main power-saver" [] { apply power-saver }
def "main sync" [] { saver-sync }
def main [] { main toggle }
