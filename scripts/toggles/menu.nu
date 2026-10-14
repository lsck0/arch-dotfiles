#!/usr/bin/env -S nu --no-config-file
use lib.nu [TOGGLES_DIR toggle-run]

const PICKER = path self ../picker.nu

def main [--fzf] {
    let toggles = ^($TOGGLES_DIR | path join status.nu) | from json | each {|t| $t | insert line $"(if $t.on { '●' } else { '○' }) ($t.label)" }
    let lines = $toggles.line | to text
    let picked = if $fzf {
        $lines | ^fzf --prompt="Toggles> " --height=~60% --border --header="enter: toggle | esc: cancel" | complete
    } else {
        $lines | ^$PICKER -p Toggles | complete
    } | get stdout | str trim
    let name = $toggles | where line == $picked | get name.0?
    if $name != null { toggle-run $name toggle }
}
