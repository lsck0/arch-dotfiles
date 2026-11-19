#!/usr/bin/env -S nu --no-config-file
# run at hyprland login: importing a pack starts the overlay, which only a running session can show

use ../../../scripts/lib/state.nu [xdg]

const MARKER = "shimoji-manual-link.done"
const SETTINGS = {BREEDING: false, WINDOW_INTERACTIONS: true}

def main []: nothing -> nothing {
    if (which shimejictl | is-empty) { return }
    let marker = xdg state $MARKER
    # the marker lists the packs imported so far: one added later, or the secrets' once the submodule is there, still
    # comes in; an import of a pack the overlay has only logs that it exists
    let done = try { open --raw $marker | lines } catch { [] }
    # private packs live in the secrets submodule, present only on an owner checkout
    let packs = [$env.FILE_PWD ($env.FILE_PWD | path join .. .. secrets state shimoji)]
        | each { glob ($in | path join "*.wlshm") } | flatten | where { ($in | path basename) not-in $done }
    # imports first: only the started overlay writes the config file the settings edit
    if ($packs | is-not-empty) {
        # the overlay makes its config root with a plain mkdir
        mkdir (xdg data)
        for pack in $packs { ^shimejictl import $pack }
        mkdir ($marker | path dirname)
        $done ++ ($packs | each { path basename }) | uniq | sort | str join "\n" | save --force $marker
    }
    $SETTINGS | items {|key, value| ^shimejictl config set $key ($value | into string) } | ignore
}
