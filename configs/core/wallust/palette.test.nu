#!/usr/bin/env -S nu --no-config-file
# palette-load and palette-rgb on a missing, a malformed and a slot-broken colors.json degrade to null; a theme loads.

use palette.nu [palette-load palette-rgb]

const THEME = path self ../../../themes/atuel-light.json

def main [] {
    let theme = open $THEME
    let cases = [
        [name content load];
        [missing null false]
        [malformed "{not json" false]
        [slot-not-hex ($theme | update colors.color3 zzz | to json) false]
        [theme ($theme | to json) true]
    ]
    let dir = mktemp --directory
    let failed = $cases | where {|c|
        let cache = $dir | path join $c.name
        mkdir ($cache | path join wal)
        if $c.content != null { $c.content | save ($cache | path join wal colors.json) }
        with-env {XDG_CACHE_HOME: $cache} {
            let p = palette-load
            let rgb = palette-rgb palette.test
            if $c.load { $p == null or $rgb == null or $p.light != "1" } else { $p != null or $rgb != null }
        }
    } | get name
    rm --recursive $dir
    if ($failed | is-not-empty) { error make {msg: $"palette.test: wrong result for ($failed | str join ', ')"} }
}
