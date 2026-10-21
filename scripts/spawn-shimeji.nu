#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname

# Pick a shimeji from `shimejictl list` and summon it.
def main []: nothing -> nothing {
    let picked = ^shimejictl list | lines | skip 1 | str replace --regex '^[0-9]+: ' '' | str join "\n"
        | do { ^($SCRIPTS | path join lib picker.nu) -p Shimeji } | complete | get stdout | str trim
    if $picked not-in ["" CNCLD] { ^shimejictl summon $picked }
}
