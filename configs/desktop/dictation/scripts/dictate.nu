#!/usr/bin/env -S nu --no-config-file
# System-wide dictation (SUPER+ALT+v): the first press records the default microphone, the second transcribes it with
# whisper.cpp (programming/nvim's pinned model, language detected) and types the text into the focused window.

const REPO = path self | path expand | path dirname --num-levels 5
use ($REPO | path join scripts lib state.nu) [unit-active xdg]

const UNIT = "dictation-record"
# programming/nvim's model pin; its mod.nu fetches the file it names into the XDG data dir
const MODEL_PIN = $REPO | path join configs programming nvim config whisper-model.json
const TAG = "string:x-canonical-private-synchronous:dictation"
const GLYPH = "\u{f036c}"
# whisper takes 16 kHz mono
const RATE_HZ = "16000"
const RECORD_MAX_SEC = "600"

def notify [title: string, body: string = ""]: nothing -> nothing {
    ^notify-send -a dictation -u low -h $TAG -h $"string:lsck0-glyph:($GLYPH)" -- $title $body | complete | ignore
}

def wav []: nothing -> path { $env.XDG_RUNTIME_DIR | path join dictation.wav }

def recording []: nothing -> bool {
    unit-active --user $"($UNIT).service"
}

def start []: nothing -> nothing {
    rm --force (wav)
    # its own unit: the recorder outlives this script, and a SIGINT stop lets pw-record finish the wav header
    ^systemd-run --user --quiet --collect $"--unit=($UNIT)" -p KillSignal=SIGINT -p $"RuntimeMaxSec=($RECORD_MAX_SEC)" pw-record --rate $RATE_HZ --channels 1 --format s16 (wav)
    notify "Dictation" "listening, SUPER+ALT+v again to type it"
}

def finish []: nothing -> nothing {
    if (recording) { ^systemctl --user stop $"($UNIT).service" }
    let model = xdg data whisper-cpp (open $MODEL_PIN | get file)
    if not ($model | path exists) { return (notify "Dictation failed" $"no whisper model at ($model)") }
    if not ((wav) | path exists) { return (notify "Dictation failed" "nothing was recorded") }
    notify "Dictation" "transcribing"
    let run = ^whisper-cli -m $model -f (wav) -l auto -nt -np | complete
    rm --force (wav)
    if $run.exit_code != 0 {
        let reason = $run.stderr | lines | str trim | where $it != "" | last 1 | str join
        return (notify "Dictation failed" $"whisper-cli exited ($run.exit_code): ($reason)")
    }
    let text = $run.stdout | lines | str trim | where $it != "" | str join " " | str replace --all --regex '\s+' " "
    if $text == "" or $text =~ '^\[[A-Z_ ]+\]$' {
        return (notify "Dictation" "heard nothing")
    }
    ^wtype -- $text
    notify "Dictated" $text
}

def main []: nothing -> nothing {
    # past RuntimeMaxSec the unit stopped on its own and the wav is finished: type it, never record over it
    let capped = ((wav) | path exists) and (ls (wav) | get 0.size) > 44b
    if (recording) or $capped { finish } else { start }
}
