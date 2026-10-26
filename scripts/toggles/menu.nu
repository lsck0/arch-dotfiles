#!/usr/bin/env -S nu --no-config-file
use lib.nu [TOGGLES_DIR toggle-run]

const PICKER = path self ../../configs/desktop/hyprland/picker.nu

# an on/off switch shows its label alone, any other toggle its state too
def line [toggle: record]: nothing -> string {
    let mark = if $toggle.on { "\u{25cf}" } else { "\u{25cb}" }
    if $toggle.states == [off on] { $"($mark) ($toggle.label)" } else { $"($mark) ($toggle.label): ($toggle.text)" }
}

def main [--fzf] {
    let toggles = ^($TOGGLES_DIR | path join status.nu) | from json | where available | sort-by --ignore-case label
        | each {|t| $t | insert line (line $t) }
    let lines = $toggles.line | to text
    let picked = if $fzf {
        $lines | ^fzf --prompt="Toggles> " --height=~60% --border --header="enter: toggle | esc: cancel" | complete
    } else {
        $lines | ^$PICKER -p Toggles | complete
    } | get stdout | str trim
    let name = $toggles | where line == $picked | get name.0?
    if $name != null { toggle-run $name toggle }
}
