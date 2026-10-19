#!/usr/bin/env -S nu --no-config-file
# hear obs: the stream mix instead of the system audio. obs has no monitor of its program mix, so every input on
# the stream track monitors to the profile's monitoring device, and app-loopback.lua (configs/desktop/pipewire)
# mutes the per-app system paths while dot.obs-listen is set and obs runs.
use lib.nu [switch-run state-get state-set state-clear state-file]
use ../../configs/desktop/quickshell/plugins/bar/widgets/obs-status.nu [config-read socket-open socket-identify request]

const STATE = "obs-listen"
# the inputs switched to monitoring, so turning it off leaves a monitor set in obs alone
const STATE_INPUTS = "obs-listen-inputs"
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

def inputs-get []: nothing -> list<string> {
    let file = state-file $STATE_INPUTS
    if ($file | path exists) { open $file | from nuon } else { [] }
}

def monitor-set [socket: int, names: list<string>, type: string]: nothing -> nothing {
    for name in $names {
        if (request $socket SetInputAudioMonitorType {inputName: $name, monitorType: $type}) == null {
            print -e $"toggle-obs-listen: SetInputAudioMonitorType\(($name)) rejected"
        }
    }
}

# every input on the stream track that monitors nothing yet; a non-audio input rejects the requests and drops out
def monitor-enable [socket: int]: nothing -> nothing {
    let names = request $socket GetInputList | get -o inputs | default [] | get inputName | where {|name|
        let tracks = request $socket GetInputAudioTracks {inputName: $name} | get -o inputAudioTracks
        let type = request $socket GetInputAudioMonitorType {inputName: $name} | get -o monitorType
        ($tracks | get -o $STREAM_TRACK) == true and $type == $MONITOR_NONE
    }
    inputs-get | append $names | uniq | to nuon | save --force (state-file $STATE_INPUTS)
    monitor-set $socket $names $MONITOR_AND_OUTPUT
}

def monitor-disable [socket: int]: nothing -> nothing {
    monitor-set $socket (inputs-get) $MONITOR_NONE
    state-clear $STATE_INPUTS
}

def listen-on []: nothing -> nothing {
    let socket = obs-connect
    monitor-enable $socket
    job kill $socket
    ^pw-metadata 0 $LISTEN_KEY 1 | ignore
    state-set $STATE on
}

# obs saves its monitor types on exit, so with obs closed they are put back at its next start (reconcile)
def listen-off []: nothing -> nothing {
    ^pw-metadata -d 0 $LISTEN_KEY | ignore
    state-clear $STATE
    let socket = try { obs-connect } catch { return }
    monitor-disable $socket
    job kill $socket
}

# run by the bar when it connects to obs: monitors and the metadata key follow the toggle state
def reconcile []: nothing -> nothing {
    let on = (state-get $STATE) == on
    if not $on and (inputs-get | is-empty) { return }
    let socket = obs-connect
    if $on {
        monitor-enable $socket
        ^pw-metadata 0 $LISTEN_KEY 1 | ignore
    } else {
        monitor-disable $socket
    }
    job kill $socket
}

def main [action: string = "toggle"] {
    if $action == reconcile {
        reconcile
        return
    }
    switch-run {
        label: "Hear OBS output"
        is-on: {|| (state-get $STATE) == on }
        on: {|| listen-on }
        off: {|| listen-off }
    } $action
}
