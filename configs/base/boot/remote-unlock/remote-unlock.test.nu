#!/usr/bin/env -S nu --no-config-file
# teardown-needed on each leftover alone, none at all, and a cmdline with only a similar word.

use mod.nu [teardown-needed]

def main [] {
    let dir = mktemp --directory
    let conf = $dir | path join initrd-wifi.conf
    let keys = $dir | path join authorized_keys
    let cmdline = $dir | path join cmdline
    let cases = [
        [name files cmdline want];
        [none [] null false]
        [wifi-conf [$conf] null true]
        [authorized-keys [$keys] null true]
        [neednet [] "root=UUID=x rd.neednet=1 quiet" true]
        [neednet-other-value [] "root=UUID=x rd.neednet=0 quiet" false]
        [neednet-absent [] "root=UUID=x quiet" false]
    ]
    let failed = $cases | where {|c|
        rm --force $conf $keys $cmdline
        for f in $c.files { touch $f }
        if $c.cmdline != null { $"($c.cmdline)\n" | save $cmdline }
        (teardown-needed [$conf $keys] $cmdline) != $c.want
    }
    rm --recursive --force $dir
    for c in $failed { print --stderr $"remote-unlock.test: ($c.name): want ($c.want)" }
    if ($failed | is-not-empty) { error make {msg: $"remote-unlock.test: ($failed | length) of ($cases | length) cases failed"} }
}
