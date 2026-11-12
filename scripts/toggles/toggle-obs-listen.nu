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
    request $socket GetInputAudioMonitorType {inputName: $name} | get --optional monitorType | default $MONITOR_NONE
}

# Live from OBS, never this script's memory.
def stream-track-inputs [socket: int]: nothing -> list<string> {
    request $socket GetInputList | get --optional inputs | default [] | get inputName | where {|name|
        (request $socket GetInputAudioTracks {inputName: $name}
            | default {} | get --optional inputAudioTracks | get --optional $STREAM_TRACK) == true
    }
}

# On, the stream-track inputs that do not monitor start to; off, every monitoring one stops.
def monitor-sync [socket: int, on: bool]: nothing -> nothing {
    let type = if $on { $MONITOR_AND_OUTPUT } else { $MONITOR_NONE }
    let names = stream-track-inputs $socket | where {|name| ((monitor-type-of $socket $name) == $MONITOR_NONE) == $on }
    for name in $names {
        if (request $socket SetInputAudioMonitorType {inputName: $name, monitorType: $type}) == null {
            print -e $"toggle-obs-listen: SetInputAudioMonitorType\(($name)) rejected"
        }
    }
}

def listen-set [on: bool]: nothing -> nothing {
    if $on {
        ^pw-metadata 0 $LISTEN_KEY 1 | ignore
        state-set $STATE on
    } else {
        ^pw-metadata -d 0 $LISTEN_KEY | ignore
        state-clear $STATE
    }
    let socket = try { obs-connect } catch { return }
    monitor-sync $socket $on
    job kill $socket
}

# A collection can carry monitor-and-output the toggle never set, which plays audio twice.
def reconcile []: nothing -> nothing {
    let on = (state-get $STATE) == on
    let socket = obs-connect
    monitor-sync $socket $on
    if $on { ^pw-metadata 0 $LISTEN_KEY 1 | ignore }
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
        on: {|| listen-set true }
        off: {|| listen-set false }
    } $action --json=$json
}
