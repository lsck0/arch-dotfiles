#!/usr/bin/env -S nu --no-config-file
# Hear the stream mix: stream-track inputs monitor, app-loopback mutes the per-app paths.

use lib.nu [switch-run state-get state-set state-clear]
use ../../configs/desktop/quickshell/plugins/bar/widgets/obs-status.nu [config-read socket-open socket-identify request]

const STATE = "obs-listen"
const LISTEN_KEY = "dot.obs-listen"
const STREAM_TRACK = "1"
const MONITOR_NONE = "OBS_MONITORING_TYPE_NONE"
const MONITOR_AND_OUTPUT = "OBS_MONITORING_TYPE_MONITOR_AND_OUTPUT"

def obs-connect []: nothing -> int {
    let config = config-read
    if $config == null { error make {msg: "obs-websocket disabled"} }
    let socket = socket-open $config.port
    socket-identify $socket $config.password
    $socket
}

def monitor-type-of [socket: int, name: string]: nothing -> string {
    request $socket GetInputAudioMonitorType {inputName: $name} | get -o monitorType | default $MONITOR_NONE
}

# Live from OBS, never this script's memory.
def stream-track-inputs [socket: int]: nothing -> list<string> {
    request $socket GetInputList | get -o inputs | default [] | get inputName | where {|name|
        (request $socket GetInputAudioTracks {inputName: $name}
            | default {} | get -o inputAudioTracks | get -o $STREAM_TRACK) == true
    }
}

def monitor-set [socket: int, names: list<string>, type: string]: nothing -> nothing {
    for name in $names {
        if (request $socket SetInputAudioMonitorType {inputName: $name, monitorType: $type}) == null {
            print -e $"toggle-obs-listen: SetInputAudioMonitorType\(($name)) rejected"
        }
    }
}

def monitor-enable [socket: int]: nothing -> nothing {
    let names = stream-track-inputs $socket | where {|name| (monitor-type-of $socket $name) == $MONITOR_NONE }
    if ($names | is-not-empty) { monitor-set $socket $names $MONITOR_AND_OUTPUT }
}

def monitor-disable [socket: int]: nothing -> nothing {
    let names = stream-track-inputs $socket | where {|name| (monitor-type-of $socket $name) != $MONITOR_NONE }
    if ($names | is-not-empty) { monitor-set $socket $names $MONITOR_NONE }
}

def listen-on []: nothing -> nothing {
    ^pw-metadata 0 $LISTEN_KEY 1 | ignore
    state-set $STATE on
    let socket = try { obs-connect } catch { return }
    monitor-enable $socket
    job kill $socket
}

def listen-off []: nothing -> nothing {
    ^pw-metadata -d 0 $LISTEN_KEY | ignore
    state-clear $STATE
    let socket = try { obs-connect } catch { return }
    monitor-disable $socket
    job kill $socket
}

# A collection can carry monitor-and-output the toggle never set, which plays audio twice.
def reconcile []: nothing -> nothing {
    let on = (state-get $STATE) == on
    let socket = obs-connect
    if $on {
        monitor-enable $socket
        ^pw-metadata 0 $LISTEN_KEY 1 | ignore
    } else {
        monitor-disable $socket
    }
    job kill $socket
}

def main [action: string = "toggle", --json] {
    if $action == reconcile {
        reconcile
        return
    }
    switch-run {
        label: "Hear OBS output"
        is-on: {|| (state-get $STATE) == on }
        on: {|| listen-on }
        off: {|| listen-off }
    } $action --json=$json
}
