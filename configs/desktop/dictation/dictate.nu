#!/usr/bin/env -S nu --no-config-file
# System-wide dictation (SUPER+ALT+v): the first press records the default microphone, the second transcribes it with
# whisper.cpp (programming/nvim's pinned model, language detected) and types the text into the focused window.

const UNIT = "dictation-record"
const MODEL = ".local/share/whisper-cpp/ggml-large-v3-turbo-q5_0.bin"
const TAG = "string:x-canonical-private-synchronous:dictation"
const GLYPH = "\u{f036c}"

def notify [title: string, body: string = ""]: nothing -> nothing {
    ^notify-send -a dictation -u low -h $TAG -h $"string:lsck0-glyph:($GLYPH)" -- $title $body | complete | ignore
}

def wav []: nothing -> path { $env.XDG_RUNTIME_DIR | path join dictation.wav }

def recording []: nothing -> bool {
    (^systemctl --user is-active --quiet $"($UNIT).service" | complete).exit_code == 0
}

def start []: nothing -> nothing {
    rm --force (wav)
    # its own unit: the recorder outlives this script, and a SIGINT stop lets pw-record finish the wav header
    ^systemd-run --user --quiet --collect $"--unit=($UNIT)" -p KillSignal=SIGINT -p RuntimeMaxSec=600 pw-record --rate 16000 --channels 1 --format s16 (wav)
    notify "Dictation" "listening, SUPER+ALT+v again to type it"
}

def finish []: nothing -> nothing {
    ^systemctl --user stop $"($UNIT).service"
    let model = $nu.home-dir | path join $MODEL
    if not ($model | path exists) { return (notify "Dictation failed" $"no whisper model at ($model)") }
    if not ((wav) | path exists) { return (notify "Dictation failed" "nothing was recorded") }
    notify "Dictation" "transcribing"
    let run = ^whisper-cli -m $model -f (wav) -l auto -nt -np | complete
    rm --force (wav)
    let text = $run.stdout | lines | str trim | where $it != "" | str join " " | str replace --all --regex '\s+' " "
    if $run.exit_code != 0 or $text == "" or $text =~ '^\[[A-Z_ ]+\]$' {
        return (notify "Dictation" "heard nothing")
    }
    ^wtype -- $text
    notify "Dictated" $text
}

def main []: nothing -> nothing {
    if (recording) { finish } else { start }
}
