#!/usr/bin/env -S nu --no-config-file
# Starts a screen recording into ~/videos/recordings, or stops the running one, which saves it. gpu-screen-recorder
# (creating/apps) runs as a transient user unit, stopped with SIGINT so it finalizes the file; the portal picks what is
# recorded and remembers the choice.

const RECORDER = "gpu-screen-recorder"
const UNIT = "screen-record.service"
const SLICE = "background-graphical.slice"
const FPS = 60
const AUDIO = "default_output"
const NOTIFY_APP = "quickshell-action"
const TITLE = "Screen recording"

def notify [body: string]: nothing -> nothing {
    ^notify-send -a $NOTIFY_APP -u low -- $TITLE $body
}

def recording-file []: nothing -> path {
    let dir = $nu.home-dir | path join videos recordings
    mkdir $dir
    $dir | path join $"(date now | format date '%Y-%m-%d_%H-%M-%S').mp4"
}

def main []: nothing -> nothing {
    if (^systemctl --user -q is-active $UNIT | complete).exit_code == 0 {
        # the unit's description is the file it writes
        let file = ^systemctl --user show -P Description $UNIT | str trim
        ^systemctl --user stop $UNIT
        notify $"Saved ($file)"
        return
    }
    if (which $RECORDER | is-empty) { notify $"($RECORDER) is not installed \(creating/apps\)"; return }
    let file = recording-file
    # a cancelled portal dialog is no failure worth the failure notifier
    let started = (^systemd-run --user --collect --unit $UNIT --slice $SLICE --description $file
        -p KillSignal=SIGINT -p OnFailure= -p SuccessExitStatus=SIGINT
        $RECORDER -w portal -restore-portal-session yes -f $FPS -a $AUDIO -o $file) | complete
    if $started.exit_code != 0 { notify $"Could not start: ($started.stderr | str trim)"; return }
    notify $"Recording to ($file), SUPER+ALT+Print stops"
}
