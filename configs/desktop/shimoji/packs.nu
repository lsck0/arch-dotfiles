#!/usr/bin/env -S nu --no-config-file
# run at hyprland login: importing a pack starts the overlay, which only a running session can show

use ../../../scripts/lib/state.nu [file-lines xdg]

const MARKER = "shimoji-manual-link.done"
const SETTINGS = {BREEDING: false, WINDOW_INTERACTIONS: true}

def main []: nothing -> nothing {
    if (which shimejictl | is-empty) { return }
    let marker = xdg state $MARKER
    # the marker lists the packs imported so far: one added later, or the secrets' once the submodule is there, still
    # comes in; an import of a pack the overlay has only logs that it exists
    let done = file-lines $marker
    # private packs live in the secrets submodule, present only on an owner checkout
    let packs = [$env.FILE_PWD ($env.FILE_PWD | path join .. .. secrets state shimoji)]
        | each { glob ($in | path join "*.wlshm") } | flatten | where { ($in | path basename) not-in $done }
    # imports first: only the started overlay writes the config file the settings edit
    if ($packs | is-not-empty) {
        # the overlay makes its config root with a plain mkdir
        mkdir (xdg data)
        # a rejected pack stays out of the marker and is retried next login; the others and the settings still go in
        let ok = $packs | where {|pack| (^shimejictl import $pack | complete).exit_code == 0 }
        let failed = $packs | where $it not-in $ok
        if ($failed | is-not-empty) { print --stderr $"shimoji: import failed: ($failed | path basename | str join ', ')" }
        mkdir ($marker | path dirname)
        $done ++ ($ok | each { path basename }) | uniq | sort | str join "\n" | save --force $marker
    }
    $SETTINGS | items {|key, value|
        let set = ^shimejictl config set $key ($value | into string) | complete
        if $set.exit_code != 0 { print --stderr $"shimoji: config set ($key) failed: ($set.stderr | str trim)" }
    } | ignore
}
