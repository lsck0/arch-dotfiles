#!/usr/bin/env -S nu --no-config-file
# phases run as systemd-run --user transient timers; TimerState.qml watches the state file

const work_default_min = 25
const break_default_min = 5
const long_default_min = 15
const long_every = 4
const unit_prefix = "quickshell-pomodoro"
const glyph = "\u{f051f}"
const alert = ($nu.home-dir | path join .config quickshell scripts alert.nu)
const phase_labels = {work: "Focus", break: "Break", long: "Long break"}

def state-path []: nothing -> path { $env.XDG_RUNTIME_DIR | path join quickshell-pomodoro state.json }

def state-load []: nothing -> record {
    if (state-path | path exists) { open (state-path) } else { {running: false, paused: false} }
}

def state-save [state: record]: nothing -> nothing {
    mkdir (state-path | path dirname)
    $state | select running paused phase endsAt cycle remaining work break long | to json -r | save -f (state-path)
}

# the app name the shell shows through dnd and keeps out of history (NotificationLogic.js ACTION_APP)
def notify [title: string, body: string = ""]: nothing -> nothing {
    ^notify-send -a quickshell-action -u low -h $"string:omarchy-glyph:($glyph)" $title $body
}

def clock [seconds: int]: nothing -> string { $"($seconds // 60):($seconds mod 60 | fill -a r -c 0 -w 2)" }

def now []: nothing -> int { date now | into int | $in // 1_000_000_000 }

# timers only: a firing phase's own service is still running
def timer-cancel []: nothing -> nothing {
    let timers = systemctl --user list-timers --all --output=json $"($unit_prefix)-*.timer" | from json | get unit
    if ($timers | is-not-empty) { systemctl --user stop ...$timers }
}

def timer-arm [seconds: int]: nothing -> nothing {
    timer-cancel
    (systemd-run --user --quiet --collect $"--on-active=($seconds)s" --timer-property=AccuracySec=1s
        $"--unit=($unit_prefix)-(now)" ($env.CURRENT_FILE | path expand) skip)
}

def phase-start [state: record, phase: string, seconds: int]: nothing -> nothing {
    state-save ($state | merge {running: true, paused: false, phase: $phase, endsAt: ((now) + $seconds), remaining: 0})
    timer-arm $seconds
}

def "main start" [work: int = $work_default_min, break: int = $break_default_min, long: int = $long_default_min]: nothing -> nothing {
    if $work <= 0 { error make {msg: "work minutes must be a positive integer"} }
    if $break <= 0 { error make {msg: "break minutes must be a positive integer"} }
    phase-start {cycle: 1, work: $work, break: $break, long: $long} work ($work * 60)
    notify $"Focus for ($work) min" "Pomodoro 1 started"
}

def "main stop" []: nothing -> nothing {
    timer-cancel
    rm -f (state-path)
    notify "Pomodoro stopped"
}

def "main pause" []: nothing -> nothing {
    let state = state-load
    if not $state.running or $state.paused { return }
    let remaining = [($state.endsAt - (now)) 0] | math max
    timer-cancel
    state-save ($state | merge {paused: true, endsAt: 0, remaining: $remaining})
    notify "Pomodoro paused" $"(clock $remaining) left"
}

def "main resume" []: nothing -> nothing {
    let state = state-load
    if not $state.paused { return }
    let remaining = if $state.remaining > 0 { $state.remaining } else { 60 }
    phase-start $state $state.phase $remaining
    notify "Pomodoro resumed" $"(clock $remaining) left"
}

def "main toggle" []: nothing -> nothing {
    let state = state-load
    if not $state.running { main start } else if $state.paused { main resume } else { main pause }
}

def "main skip" []: nothing -> nothing {
    let state = state-load
    if not $state.running { return }
    if $state.phase == work {
        let next = if $state.cycle mod $long_every == 0 { "long" } else { "break" }
        let minutes = $state | get $next
        phase-start $state $next ($minutes * 60)
        ^$alert "Focus block done" $"Take a ($phase_labels | get $next | str lowercase), ($minutes) min" $glyph pomodoro
    } else {
        let cycle = $state.cycle + 1
        phase-start ($state | merge {cycle: $cycle}) work ($state.work * 60)
        ^$alert "Break over" $"Focus for ($state.work) min, pomodoro ($cycle)" $glyph pomodoro
    }
}

def "main status" [--json (-j)]: nothing -> nothing {
    let state = state-load
    let status = if not $state.running {
        {
            running: false, paused: false, phase: idle, label: Pomodoro, remainingSeconds: 0, remaining: "", cycle: 0,
            totalSeconds: 0, defaultWork: $work_default_min, longEvery: $long_every, tooltip: "Pomodoro: off"
        }
    } else {
        let remaining = [(if $state.paused { $state.remaining } else { $state.endsAt - (now) }) 0] | math max
        let label = $phase_labels | get $state.phase
        let paused_note = if $state.paused { " (paused)" } else { "" }
        {
            running: true, paused: $state.paused, phase: $state.phase, label: $label, remainingSeconds: $remaining,
            remaining: (clock $remaining), cycle: $state.cycle,
            totalSeconds: (($state | get $state.phase) * 60),
            longEvery: $long_every, tooltip: $"($label) :: (clock $remaining) left :: pomodoro ($state.cycle)($paused_note)"
        }
    }
    print (if $json { $status | to json -r } else { $status.tooltip })
}

def main []: nothing -> nothing { main status }
