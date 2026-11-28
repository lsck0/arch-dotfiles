#!/usr/bin/env -S nu --no-config-file
# every platform's autostart entry for fluxer opens the DevTools port fluxer-voice.nu reads (that launch bypasses the
# desktop file)

use scripts/fluxer-voice.nu [DEVTOOLS_PORT]

const PLATFORMS = path self ../../../platforms

def main [] {
    for file in (glob ($PLATFORMS | path join *.options.nuon)) {
        let entries = open $file | get --optional desktop/hyprland.autostart | default []
        for entry in ($entries | where {|e| $e.cmd | str starts-with fluxer }) {
            if not ($entry.cmd | str contains $"--remote-debugging-port=($DEVTOOLS_PORT)") {
                error make {msg: $"($file | path basename) autostart `($entry.cmd)` lacks --remote-debugging-port=($DEVTOOLS_PORT)"}
            }
        }
    }
}
