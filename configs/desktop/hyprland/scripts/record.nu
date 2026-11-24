#!/usr/bin/env -S nu --no-config-file
# Starts a screen recording into ~/videos/recordings, or stops the running one, which saves it. gpu-screen-recorder
# (creating/apps) runs as a transient user unit, stopped with SIGINT so it finalizes the file; the portal picks what is
# recorded and remembers the choice. The bar's recording indicator reads the unit on each `toggles changed record.nu`.

const RECORDER = "gpu-screen-recorder"
const UNIT = "screen-record.service"
const SLICE = "background-graphical.slice"
const FPS = 60
const AUDIO = "default_output"
const NOTIFY_APP = "quickshell-action"
const TITLE = "Screen recording"
const IPC_TIMEOUT = "3s"

def notify [body: string]: nothing -> nothing {
    ^notify-send -a $NOTIFY_APP -u low -- $TITLE $body
}

def recording-active []: nothing -> bool { (^systemctl --user -q is-active $UNIT | complete).exit_code == 0 }

def recording-stop []: nothing -> nothing {
    # the unit's description is the file it writes
    let file = ^systemctl --user show -P Description $UNIT | str trim
    ^systemctl --user stop $UNIT
    notify $"Saved ($file)"
}

# Bounded and inline, not quickshell's shell.nu: hyprland applies before quickshell, so that copy may be missing or stale.
def bar-ping []: nothing -> list<string> {
    [timeout $IPC_TIMEOUT quickshell ipc -p ($nu.home-dir | path join .config quickshell) call toggles changed record.nu]
}

def recording-file []: nothing -> path {
    let dir = $nu.home-dir | path join videos recordings
    mkdir $dir
    $dir | path join $"(date now | format date '%Y-%m-%d_%H-%M-%S').mp4"
}

# Stops only, so the bar's stop button never starts a recording that ended a moment before the press.
def "main stop" []: nothing -> nothing {
    if (recording-active) { recording-stop }
}

def main []: nothing -> nothing {
    if (recording-active) { recording-stop; return }
    if (which $RECORDER | is-empty) { notify $"($RECORDER) is not installed \(creating/apps\)"; return }
    let file = recording-file
    # ExecStopPost pings the bar however the recorder ends (stopped, crashed, portal dialog cancelled); "-" keeps a shell
    # that is down from failing the unit. A cancelled portal dialog is no failure worth the failure notifier.
    let ping = "-" + (bar-ping | str join ' ')
    let started = (^systemd-run --user --collect --unit $UNIT --slice $SLICE --description $file
        -p KillSignal=SIGINT -p OnFailure= -p SuccessExitStatus=SIGINT -p $"ExecStopPost=($ping)"
        $RECORDER -w portal -restore-portal-session yes -f $FPS -a $AUDIO -o $file) | complete
    if $started.exit_code != 0 { notify $"Could not start: ($started.stderr | str trim)"; return }
    run-external ...(bar-ping) | complete | ignore
    notify $"Recording to ($file), SUPER+ALT+Print stops"
}
