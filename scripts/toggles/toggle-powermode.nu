#!/usr/bin/env -S nu --no-config-file
use lib.nu [status-record status-print notify notify-failed root-run state-get state-set state-clear state-file shell-call cycle-next exclusive-run state-check hyprland-instance]
use ../lib/log.nu [log-err]
use ../lib/platform.nu [platform-load]
use ../../configs/desktop/hyprland/scripts/reload.nu [hyprland-reload]

# auto is no forced mode: tlp picks by the power source
const MODES = {auto: Auto, balanced: Balanced, performance: Performance, power-saver: "Power saver"}
const REPO = path self ../..
# tlp's own record of a forced profile (tlp-func-base's MANUALMODEFILE): gone after any tlp start, a restart included
const TLP_MANUAL = "/run/tlp/manual_mode"
const TLP_PROFILES = {"0": performance, "1": balanced, "2": power-saver}

# tlp's mode; its record unreadable (a root umask), the last one forced here
def current []: nothing -> string {
    if not ($TLP_MANUAL | path exists) { return "auto" }
    let code = try { open --raw $TLP_MANUAL | str trim } catch { "" }
    if $code in $TLP_PROFILES { return ($TLP_PROFILES | get $code) }
    state-get powermode --volatile | if $in in $MODES and $in != auto { $in } else { "auto" }
}

def on-battery []: nothing -> bool {
    (platform-load $REPO).form_factor == laptop and (
        ^busctl get-property org.freedesktop.UPower /org/freedesktop/UPower org.freedesktop.UPower OnBattery | complete
    ).stdout == "b true\n"
}

# The one saver rule: forced power-saver, or auto on a laptop's battery; a forced balanced or performance wins.
def saver []: nothing -> bool {
    match (current) { power-saver => true, auto => (on-battery), _ => false }
}

def saver-log-err [saver: string, msg: string]: nothing -> nothing {
    with-env {LOG_TAG: ($env.PROCESS_PATH | path basename)} { log-err $"power saver ($saver): ($msg)" }
}

# Reloads ghostty, hyprland (with the monitor layout and the shader) and the bar, only when the saver state flips.
def saver-sync []: nothing -> nothing {
    let saver = if (saver) { "on" } else { "off" }
    if (state-get powersaver --volatile) == $saver { return }
    state-set powersaver $saver --volatile
    let ghostty_conf = state-file ghostty-powersave.conf --volatile
    if $saver == on { "cursor-style-blink = false\n" | save --force $ghostty_conf } else { rm --force $ghostty_conf }
    # desktop/ghostty links it, and complete does not catch a command that is not there
    if (which ghostty-reload | is-not-empty) {
        let run = ^ghostty-reload | complete
        if $run.exit_code != 0 { saver-log-err $saver $"ghostty-reload failed: ($run.stderr | str trim | lines | last 1 | str join '')" }
    }
    # outside a Hyprland session (a tty, a unit) there is nothing to reload
    if (hyprland-instance) != "" { try { hyprland-reload } catch {|err| saver-log-err $saver $err.msg } }
    shell-call shell reloadPowerMode | complete | ignore
}

def "main _apply" [mode: string]: nothing -> nothing {
    try { root-run tlp (if $mode == auto { "start" } else { $mode }) } catch {|err|
        notify-failed "Power mode" $err.msg --to ($MODES | get $mode) --now ($MODES | get (current))
        exit 1
    }
    if $mode == auto { state-clear powermode --volatile } else { state-set powermode $mode --volatile }
    saver-sync
    notify "Power mode" ($MODES | get $mode)
}

def "main get" [--json] {
    let mode = current
    let available = which tlp | is-not-empty
    status-print (status-record "Power mode" $mode --text ($MODES | get $mode) --states ($MODES | columns) --available=$available) $json
}

# auto is a stop of its own: else the first press leaves it for good
def "main toggle" [] { main set ($MODES | columns | cycle-next (current)) }
def "main set" [mode: string] {
    state-check "power mode" $mode ($MODES | columns)
    exclusive-run "Power mode" _apply $mode
}
def "main auto" [] { main set auto }
def "main balanced" [] { main set balanced }
def "main performance" [] { main set performance }
def "main power-saver" [] { main set power-saver }
def "main sync" [] { saver-sync }
# Power mode: get [--json] prints the mode, set <mode> or the mode's own name (auto, balanced,
# performance, power-saver) switches to it, toggle takes the next one, a bare call toggles.
def main [] { main toggle }
