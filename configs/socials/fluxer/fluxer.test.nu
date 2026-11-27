#!/usr/bin/env -S nu --no-config-file
# fluxer-voice.nu reads the port the launcher opens: its PORT equals mod.nu's DEVTOOLS_PORT

use mod.nu [DEVTOOLS_PORT]

const HERE = path self .

def main [] {
    let script = open --raw ($HERE | path join scripts fluxer-voice.nu)
    let port = $script | parse --regex '(?m)^const PORT = (?<p>\d+)$' | get --optional 0.p
    if $port == null or ($port | into int) != $DEVTOOLS_PORT {
        error make {msg: $"scripts/fluxer-voice.nu PORT ($port) is not mod.nu's DEVTOOLS_PORT ($DEVTOOLS_PORT)"}
    }
}
