#!/usr/bin/env -S nu --no-config-file
# offload's idle gate, the login's half (offload-gate.service): gamemode's ClientCount on the session bus and obs's
# stream and record outputs over obs-websocket (the bar's obs-status.nu client) into /run/offload/gate/<uid>.json,
# which every user's worker reads; the worker reads the power itself. Written on each change only, so the change
# triggers offload-enforce.path in each manager.

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join configs desktop quickshell plugins bar widgets obs-status.nu) [config-read socket-open socket-identify request]
use ($REPO | path join configs programming offload worker.nu) [state-at]

const GATE_DIR = "/run/offload/gate"
const GAMEMODE = [com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode]
const TAG_GAMEMODE = 7
# while obs is away the next connect tries after this; while connected only its events wake the loop
const OBS_RETRY = 5sec
const RESYNC = 5min

def gamemode-active []: nothing -> bool {
    let got = do { ^busctl --user get-property ...$GAMEMODE ClientCount } | complete
    ($got.exit_code == 0) and (($got.stdout | str trim | split row " " | get --optional 1 | default "0") != "0")
}

def obs-active [socket: int]: nothing -> bool {
    let stream = request $socket GetStreamStatus
    let record = request $socket GetRecordStatus
    if $stream == null or $record == null { error make {msg: "obs left a status unanswered"} }
    $stream.outputActive? == true or $record.outputActive? == true
}

def obs-connect []: nothing -> any {
    let config = config-read
    if $config == null { return null }
    let socket = socket-open $config.port
    try { socket-identify $socket $config.password; $socket } catch { try { job kill $socket }; null }
}

def state-write [state: record]: nothing -> nothing {
    let dir = state-at $GATE_DIR
    let file = $dir | path join $"(^id -u | str trim).json"
    let tmp = ^mktemp --tmpdir=($dir) .gate.XXXXXX | str trim
    $state | to json --raw | save --force $tmp
    ^chmod 644 $tmp
    ^mv --force $tmp $file
}

def main []: nothing -> nothing {
    job spawn {
        ^gdbus monitor --session --dest ($GAMEMODE | first) | lines | each { {gamemode: true} | job send --tag $TAG_GAMEMODE 0 }
        | ignore
    }
    mut socket: any = null
    mut obs = false
    mut last: any = null
    loop {
        if $socket == null { $socket = obs-connect }
        let active = if $socket != null { try { obs-active $socket } catch { null } }
        if $active == null and $socket != null {
            try { job kill $socket }
            $socket = null
        }
        $obs = $active == true
        let state = {gamemode: (gamemode-active), obs: $obs}
        if $state != $last {
            state-write $state
            $last = $state
        }
        let wait = if $socket == null { $OBS_RETRY } else { $RESYNC }
        # any message re-reads both: a gamemode signal, an obs event, obs closing ({op: null}, its socket job ended)
        let message = try { job recv --timeout $wait } catch { null }
        if ($message | describe) =~ '^record' and ("op" in ($message | columns)) and $message.op == null {
            try { job kill $socket }
            $socket = null
        }
    }
}
