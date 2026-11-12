#!/usr/bin/env -S nu --no-config-file
# run at hyprland login: importing a pack starts the overlay, which only a running session can show

use ../../../scripts/lib/state.nu [xdg]

const MARKER = "shimoji-manual-link.done"
const SETTINGS = {BREEDING: false, WINDOW_INTERACTIONS: true}

def main []: nothing -> nothing {
    if (which shimejictl | is-empty) { return }
    let marker = xdg state $MARKER
    # imports first: only the started overlay writes the config file the settings edit
    if not ($marker | path exists) {
        # the overlay makes its config root with a plain mkdir
        mkdir (xdg data)
        # private packs live in the secrets submodule, present only on an owner checkout
        let packs = [$env.FILE_PWD ($env.FILE_PWD | path join .. .. secrets state shimoji)] | each { glob ($in | path join "*.wlshm") } | flatten
        for pack in $packs { ^shimejictl import $pack }
        mkdir ($marker | path dirname)
        touch $marker
    }
    $SETTINGS | items {|key, value| ^shimejictl config set $key ($value | into string) } | ignore
}
