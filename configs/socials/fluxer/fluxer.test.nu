#!/usr/bin/env -S nu --no-config-file
# fluxer-voice.nu reads the port the launcher opens: its PORT equals mod.nu's DEVTOOLS_PORT, and every platform's
# autostart entry for fluxer opens it too (that launch bypasses the desktop file)

use mod.nu [DEVTOOLS_PORT]

const HERE = path self .
const PLATFORMS = path self ../../../platforms

def main [] {
    let script = open --raw ($HERE | path join scripts fluxer-voice.nu)
    let port = $script | parse --regex '(?m)^const PORT = (?<p>\d+)$' | get --optional 0.p
    if $port == null or ($port | into int) != $DEVTOOLS_PORT {
        error make {msg: $"scripts/fluxer-voice.nu PORT ($port) is not mod.nu's DEVTOOLS_PORT ($DEVTOOLS_PORT)"}
    }
    for file in (glob ($PLATFORMS | path join *.options.nuon)) {
        let entries = open $file | get --optional desktop/hyprland.autostart | default []
        for entry in ($entries | where {|e| $e.cmd | str starts-with fluxer }) {
            if not ($entry.cmd | str contains $"--remote-debugging-port=($DEVTOOLS_PORT)") {
                error make {msg: $"($file | path basename) autostart `($entry.cmd)` lacks --remote-debugging-port=($DEVTOOLS_PORT)"}
            }
        }
    }
}
