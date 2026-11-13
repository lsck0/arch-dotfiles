#!/usr/bin/env -S nu --no-config-file

# expanded first: called through its ~/.local/bin link, path self alone is the link's dir
const PICKER = path self | path expand | path dirname --num-levels 2 | path join configs desktop hyprland picker.nu

# Pick a shimeji from `shimejictl list` and summon it.
def main []: nothing -> nothing {
    let picked = ^shimejictl list | lines | skip 1 | str replace --regex '^[0-9]+: ' '' | str join "\n"
        | do { ^$PICKER -p Shimeji } | complete | get stdout | str trim
    if $picked != "" { ^shimejictl summon $picked }
}
