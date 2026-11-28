#!/usr/bin/env -S nu --no-config-file
# every platform's autostart entry for fluxer opens the DevTools port fluxer-voice.nu reads (that launch bypasses the
# desktop file). fluxer-voice.nu reads the port only from a listener of its own uid: a free port is none, one this
# test opens is own.

use std/assert
use scripts/fluxer-voice.nu [DEVTOOLS_PORT listener-owner]

const PLATFORMS = path self ../../../platforms

# a listener of this uid on a port the kernel picked, which it writes with its pid to argv[1]
const LISTENER = "import os, socket, sys, time
s = socket.socket(); s.bind(('127.0.0.1', 0)); s.listen()
open(sys.argv[1], 'w').write(f'{s.getsockname()[1]} {os.getpid()}')
time.sleep(10)"
const LISTENER_WAIT = 3sec

def listener-owners []: nothing -> nothing {
    if (which python3 ss | length) < 2 { return }
    let file = mktemp --tmpdir dot-fluxer-test-XXXXXX
    rm $file
    # killed below once read: its SIGTERM exit is the expected end
    job spawn { ^python3 -I -c $LISTENER $file | complete | ignore } | ignore
    let start = date now
    while not ($file | path exists) or (open --raw $file | is-empty) {
        assert ((date now) - $start < $LISTENER_WAIT) "fluxer-voice test: the listener did not start"
        sleep 50ms
    }
    let l = open --raw $file | parse "{port} {pid}" | get 0
    rm $file
    let port = $l.port | into int
    let owned = listener-owner $port
    ^kill $l.pid
    assert equal $owned own "fluxer-voice: its own listener is not own"
    sleep 100ms
    assert equal (listener-owner $port) none "fluxer-voice: a free port is not none"
}

def main [] {
    listener-owners
    for file in (glob ($PLATFORMS | path join *.options.nuon)) {
        let entries = open $file | get --optional desktop/hyprland.autostart | default []
        for entry in ($entries | where {|e| $e.cmd | str starts-with fluxer }) {
            if not ($entry.cmd | str contains $"--remote-debugging-port=($DEVTOOLS_PORT)") {
                error make {msg: $"($file | path basename) autostart `($entry.cmd)` lacks --remote-debugging-port=($DEVTOOLS_PORT)"}
            }
        }
    }
}
