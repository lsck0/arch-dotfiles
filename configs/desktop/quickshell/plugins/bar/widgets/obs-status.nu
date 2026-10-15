#!/usr/bin/env -S nu --no-config-file
# streams obs state as JSON lines, applies JSON commands read from stdin; exits when stdin closes

const CONFIG_RELATIVE = "obs-studio/plugin_config/obs-websocket/config.json"
const PORT_DEFAULT = 4455
# obs-websocket 5.x event subscriptions: general, scenes, inputs, outputs
const SUBSCRIPTIONS = 0b1001101
const EVENTS_REPOLL = [StreamState RecordState CurrentProgramScene Exit InputMuteStateChanged]
const MUTE_SOURCES = {Mic: "Mic/Aux", Desktop: "Desktop Audio", Game: "Game Audio"}
# cmd -> [requestType, payload key]
const COMMANDS = {
    toggleStream: [ToggleStream null]
    toggleRecord: [ToggleRecord null]
    toggleRecordPause: [ToggleRecordPause null]
    toggleReplay: [ToggleReplayBuffer null]
    saveReplay: [SaveReplayBuffer null]
    setScene: [SetCurrentProgramScene sceneName]
}
const OP_HELLO = 0
const OP_IDENTIFY = 1
const OP_IDENTIFIED = 2
const OP_EVENT = 5
const OP_REQUEST = 6
const POLL_ACTIVE = 1sec
const POLL_IDLE = 5sec
const RECV_TIMEOUT = 6sec
const REQUEST_TIMEOUT = 5sec
const RECONNECT_MIN = 1sec
const RECONNECT_MAX = 5sec
const RECONNECT_GROWTH = 1.6
const ERROR_LENGTH_MAX = 120
const MAIN_JOB = 0
# mailbox tags: replies and the close marker are awaited by tag, events and stdin wake the main loop
const TAG_SOCKET = 1
const TAG_EVENT = 2
const TAG_STDIN = 3

def config-read []: nothing -> any {
    let path = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join $CONFIG_RELATIVE
    let config = try { open $path } catch { return null }
    if $config.server_enabled? != true { return null }
    {port: ($config.server_port? | default $PORT_DEFAULT), password: ($config.server_password? | default "")}
}

def sha256-base64 []: string -> string { hash sha256 --binary | encode base64 }

def socket-recv []: nothing -> record {
    let message = try { job recv --tag $TAG_SOCKET --timeout $RECV_TIMEOUT } catch { error make {msg: "obs-websocket timed out"} }
    if $message.op == null { error make {msg: "connection closed"} }
    $message
}

def socket-send [socket: int, message: record]: nothing -> nothing { $message | to json -r | job send $socket }

# the reply is matched by requestId since events interleave; null when obs rejects it
def request [socket: int, type: string, data: record = {}]: nothing -> any {
    let id = random uuid
    socket-send $socket {op: $OP_REQUEST, d: {requestType: $type, requestId: $id, requestData: $data}}
    let deadline = (date now) + $REQUEST_TIMEOUT
    loop {
        if (date now) > $deadline { return null }
        let reply = socket-recv
        if $reply.d.requestId? == $id {
            return (if $reply.d.requestStatus.result { $reply.d.responseData? | default {} })
        }
    }
}

def socket-open [port: int]: nothing -> int {
    # a reply or close left over from the previous session would be read as this one's
    while (try { job recv --tag $TAG_SOCKET --timeout 0sec; true } catch { false }) { }
    job spawn {
        try {
            generate {|_| {out: (job recv), next: 0}} 0 | to text
            | ^websocat --text --exit-on-eof $"ws://127.0.0.1:($port)" e> /dev/null
            | lines | each {|line|
                let message = $line | from json
                $message | job send --tag (if $message.op == $OP_EVENT { $TAG_EVENT } else { $TAG_SOCKET }) $MAIN_JOB
            } | ignore
        }
        {op: null} | job send --tag $TAG_SOCKET $MAIN_JOB
    }
}

def socket-identify [socket: int, password: string]: nothing -> nothing {
    let hello = socket-recv
    if $hello.op != $OP_HELLO { error make {msg: "unexpected greeting"} }
    let auth = $hello.d.authentication?
    let identify = {rpcVersion: ($hello.d.rpcVersion? | default 1), eventSubscriptions: $SUBSCRIPTIONS}
    let identify = if $auth == null { $identify } else {
        if ($password | is-empty) { error make {msg: "auth required but no password in config"} }
        let secret = $password + $auth.salt | sha256-base64
        $identify | insert authentication ($secret + $auth.challenge | sha256-base64)
    }
    socket-send $socket {op: $OP_IDENTIFY, d: $identify}
    if (socket-recv).op != $OP_IDENTIFIED { error make {msg: "identify rejected"} }
}

def round-to [digits: int]: any -> float { default 0 | into float | math round --precision $digits }

def timecode-seconds []: any -> int {
    default "" | str replace -r '\..*' '' | split row ":" | where $it != "" | into int | reverse | enumerate
    | each {|part| $part.item * (60 ** $part.index) } | math sum
}

def snapshot [socket: int]: nothing -> record {
    let stats = request $socket GetStats | default {}
    let stream = request $socket GetStreamStatus | default {}
    let record = request $socket GetRecordStatus | default {}
    let scene = request $socket GetCurrentProgramScene | default {}
    let scenes = request $socket GetSceneList | default {}
    # a label the loaded collection lacks is dropped, the widget only sees inputs that exist
    let inputs = $MUTE_SOURCES | transpose label name | each {|input|
        let mute = request $socket GetInputMute {inputName: $input.name}
        let volume = request $socket GetInputVolume {inputName: $input.name}
        {label: $input.label, mute: ($mute | get -o inputMuted), volume: ($volume | get -o inputVolumeMul)}
    }
    let sent = $stream.outputTotalFrames? | default 0
    let skipped = $stream.outputSkippedFrames? | default 0
    {
        connected: true
        streaming: ($stream.outputActive? == true)
        streamReconnecting: ($stream.outputReconnecting? == true)
        recording: ($record.outputActive? == true)
        recordPaused: ($record.outputPaused? == true)
        streamSeconds: ($stream.outputTimecode? | timecode-seconds)
        recordSeconds: ($record.outputTimecode? | timecode-seconds)
        streamBytes: ($stream.outputBytes? | default 0)
        recordBytes: ($record.outputBytes? | default 0)
        congestion: ($stream.outputCongestion? | round-to 3)
        droppedFrames: $skipped
        dropPct: (if $sent > 0 { $skipped * 100.0 / $sent | round-to 2 } else { 0.0 })
        fps: ($stats.activeFps? | round-to 1)
        cpu: ($stats.cpuUsage? | round-to 1)
        memMb: ($stats.memoryUsage? | round-to 1)
        freeDiskMb: ($stats.availableDiskSpace? | round-to 1)
        frameTimeMs: ($stats.averageFrameRenderTime? | round-to 2)
        renderSkipped: ($stats.renderSkippedFrames? | default 0)
        renderTotal: ($stats.renderTotalFrames? | default 0)
        encoderSkipped: ($stats.outputSkippedFrames? | default 0)
        encoderTotal: ($stats.outputTotalFrames? | default 0)
        scene: ($scene.currentProgramSceneName? | default "")
        # obs lists scenes bottom first
        scenes: ($scenes.scenes? | default [] | reverse | get -o sceneName | compact --empty)
        mutes: ($inputs | where mute != null | each {|i| [$i.label $i.mute] } | into record)
        volumes: ($inputs | where volume != null | each {|i| [$i.label ($i.volume | round-to 4)] } | into record)
    }
}

# true when a status re-poll is warranted
def command-apply [socket: int, line: string]: nothing -> bool {
    # stdin is the widget's and the keybind's, not trusted to be JSON
    let message = try { $line | from json | into record } catch { return false }
    let cmd = $message.cmd? | default ""
    if $cmd in [toggleMute setInputVolume] {
        let input = $MUTE_SOURCES | get -o ($message.source? | default "")
        if $input == null { return false }
        if $cmd == toggleMute {
            if (request $socket ToggleInputMute {inputName: $input}) == null {
                print -e $"obs-status: ToggleInputMute\(($input)) rejected"
            }
            return true
        }
        let volume = try { $message.volume | into float } catch { return false }
        let volume = [([$volume 0.0] | math max) 1.0] | math min
        if (request $socket SetInputVolume {inputName: $input, inputVolumeMul: $volume}) == null {
            print -e $"obs-status: SetInputVolume\(($input)) rejected"
        }
        # the widget already moved its fader; a re-poll would fight a live drag
        return false
    }
    let entry = $COMMANDS | get -o $cmd
    if $entry == null { return false }
    let data = if $entry.1 == null { {} } else {
        if ($message.scene? | is-empty) { return false }
        {($entry.1): ($message.scene | into string)}
    }
    if (request $socket $entry.0 $data) == null { print -e $"obs-status: ($entry.0) rejected" }
    true
}

def emit [payload: record, last: string]: nothing -> string {
    let line = $payload | to json -r
    if $line != $last { print $line }
    $line
}

def main [] {
    job spawn {
        ^cat | lines | each {|line| {stdin: $line} | job send --tag $TAG_STDIN $MAIN_JOB } | ignore
        {eof: true} | job send --tag $TAG_STDIN $MAIN_JOB
    }
    mut last = emit {connected: false} ""
    mut backoff = $RECONNECT_MIN
    loop {
        let config = config-read
        if $config == null {
            $last = emit {connected: false, error: "obs-websocket disabled"} $last
            sleep $RECONNECT_MAX
            continue
        }
        let socket = socket-open $config.port
        let failure = try {
            socket-identify $socket $config.password
            mut due = true
            mut polled = date now
            mut active = false
            loop {
                let interval = if $active { $POLL_ACTIVE } else { $POLL_IDLE }
                if $due or (date now) - $polled >= $interval {
                    let state = snapshot $socket
                    $active = $state.streaming or $state.recording
                    $last = emit $state $last
                    $polled = date now
                    $due = false
                }
                # a timeout is the next poll tick
                let message = try { job recv --timeout ($interval - ((date now) - $polled)) } catch { null }
                if $message == null { continue }
                if $message.eof? == true { exit 0 }
                if $message.stdin? != null {
                    $due = command-apply $socket $message.stdin
                } else if $message.op == null {
                    error make {msg: "connection closed"}
                } else if $message.op == $OP_EVENT and ($EVENTS_REPOLL | any {|prefix| $message.d.eventType | str starts-with $prefix }) {
                    $due = true
                }
            }
        } catch {|error| $error.msg }
        # gone already when websocat exited on its own
        try { job kill $socket }
        $last = emit {connected: false, error: ($failure | str substring 0..<$ERROR_LENGTH_MAX)} $last
        sleep $backoff
        $backoff = [$RECONNECT_MAX ($backoff * $RECONNECT_GROWTH)] | math min
    }
}
