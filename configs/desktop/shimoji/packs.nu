#!/usr/bin/env -S nu --no-config-file
# imports the mascot packs once and sets the overlay's settings; run at hyprland login (hyprland_autostart.lua), since
# importing a pack starts the overlay, which only a running session can show

const MARKER = ".local/state/shimoji-manual-link.done"
# window interactions let mascots climb and sit on windows
const SETTINGS = {BREEDING: false, WINDOW_INTERACTIONS: true}

def main []: nothing -> nothing {
    if (which shimejictl | is-empty) { return }
    let marker = $nu.home-dir | path join $MARKER
    # first, since an import starts the overlay and only that writes the config file the settings edit
    if not ($marker | path exists) {
        # the overlay makes its config root with a plain mkdir, so the parent has to be there
        mkdir ($nu.home-dir | path join .local share)
        for pack in (glob ($env.FILE_PWD | path join "*.wlshm")) { ^shimejictl import $pack }
        mkdir ($marker | path dirname)
        touch $marker
    }
    $SETTINGS | items {|key, value| ^shimejictl config set $key ($value | into string) } | ignore
}
