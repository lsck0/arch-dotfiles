#!/usr/bin/env -S nu --no-config-file
# run at hyprland login: importing a pack starts the overlay, which only a running session can show

const MARKER = "shimoji-manual-link.done"
const SETTINGS = {BREEDING: false, WINDOW_INTERACTIONS: true}

def main []: nothing -> nothing {
    if (which shimejictl | is-empty) { return }
    let state = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state)
    let marker = $state | path join $MARKER
    # imports first: only the started overlay writes the config file the settings edit
    if not ($marker | path exists) {
        # the overlay makes its config root with a plain mkdir
        mkdir ($env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share))
        for pack in (glob ($env.FILE_PWD | path join "*.wlshm")) { ^shimejictl import $pack }
        mkdir ($marker | path dirname)
        touch $marker
    }
    $SETTINGS | items {|key, value| ^shimejictl config set $key ($value | into string) } | ignore
}
