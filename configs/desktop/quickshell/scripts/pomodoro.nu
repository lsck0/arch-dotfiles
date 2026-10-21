#!/usr/bin/env -S nu --no-config-file

const config_path = ($nu.home-dir | path join .config quickshell pomodoro.json)
const config_default = {focus: 25, break: 5, long: 15, cycles: 4}
const option_names = {
    focus: pomodoro_focus_min, break: pomodoro_break_min, long: pomodoro_long_break_min, cycles: pomodoro_cycles
}
const dot = ($nu.home-dir | path join .local bin dot)
const unit_prefix = "quickshell-pomodoro"
const glyph = "\u{f051f}"
const phase_labels = {work: "Focus", break: "Break", long: "Long break"}
const chime = ($nu.home-dir | path join .config quickshell sounds pomodoro.oga)
const chime_volume = 0.3
const chime_timeout = "3s"

def config-load []: nothing -> record {
    $config_default | merge (try { open $config_path } catch { {} })
}

def state-path []: nothing -> path { $env.XDG_RUNTIME_DIR | path join quickshell-pomodoro state.json }

def state-load []: nothing -> record {
    if (state-path | path exists) { open (state-path) } else { {running: false, paused: false} }
}

def state-save [state: record]: nothing -> nothing {
    mkdir (state-path | path dirname)
    $state | select --optional running paused phase endsAt cycle remaining work break long cycles | to json -r | save -f (state-path)
}

# Sent as the app the shell shows through dnd and keeps out of history (NotificationLogic.js ACTION_APP).
def notify [title: string, body: string = ""]: nothing -> nothing {
    ^notify-send -a quickshell-action -u low -h $"string:omarchy-glyph:($glyph)" $title $body
}

# Plays in the foreground: the timer's unit kills background children on exit.
def chime-play []: nothing -> nothing {
    if ($chime | path exists) { ^timeout $chime_timeout pw-play --media-role Notification --volume $chime_volume $chime | complete | ignore }
}

def clock [seconds: int]: nothing -> string { $"($seconds // 60):($seconds mod 60 | fill -a r -c 0 -w 2)" }

def now []: nothing -> int { date now | into int | $in // 1_000_000_000 }

def timer-cancel []: nothing -> nothing {
    let timers = systemctl --user list-timers --all --output=json $"($unit_prefix)-*.timer" | from json | get unit
    if ($timers | is-not-empty) { systemctl --user stop ...$timers }
}

# Nanoseconds in the unit name: two skips in one second would otherwise collide.
def timer-arm [seconds: int]: nothing -> nothing {
    timer-cancel
    (systemd-run --user --quiet --collect $"--on-active=($seconds)s" --timer-property=AccuracySec=1s
        $"--unit=($unit_prefix)-(date now | into int)" ($env.CURRENT_FILE | path expand) _elapsed)
}

def phase-start [state: record, phase: string, seconds: int]: nothing -> nothing {
    state-save ($state | merge {running: true, paused: false, phase: $phase, endsAt: ((now) + $seconds), remaining: 0})
    timer-arm $seconds
}

def phase-advance [--chime]: nothing -> nothing {
    let state = state-load
    if not $state.running { return }
    let config = config-load
    let lengths = {work: $config.focus, break: $config.break, long: $config.long, cycles: $config.cycles}
    if $state.phase == work {
        let next = if $state.cycle mod $config.cycles == 0 { "long" } else { "break" }
        let minutes = $lengths | get $next
        phase-start ($state | merge $lengths) $next ($minutes * 60)
        notify "Focus block done" $"($phase_labels | get $next) for ($minutes) min"
    } else {
        let cycle = $state.cycle + 1
        phase-start ($state | merge $lengths | merge {cycle: $cycle}) work ($config.focus * 60)
        notify "Break over" $"Focus for ($config.focus) min, pomodoro ($cycle)"
    }
    if $chime { chime-play }
}

def "main start" []: nothing -> nothing {
    let config = config-load
    phase-start {cycle: 1, work: $config.focus, break: $config.break, long: $config.long, cycles: $config.cycles} work ($config.focus * 60)
    notify $"Focus for ($config.focus) min" "Pomodoro 1 started"
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

def "main skip" []: nothing -> nothing { phase-advance }

# the timer's own command
def "main _elapsed" []: nothing -> nothing { phase-advance --chime }

# the lengths in minutes and the focus blocks before a long break, as json
def "main config" []: nothing -> nothing { print (config-load | to json -r) }

# set <key> <value> ...: focus, break, long (minutes) or cycles, stored as the module's options
def "main set" [...pairs: string]: nothing -> nothing {
    if ($pairs | is-empty) or ($pairs | length) mod 2 != 0 { error make {msg: "want <key> <value> pairs, keys: focus break long cycles"} }
    for pair in ($pairs | chunks 2) {
        let option = $option_names | get --optional $pair.0
        if $option == null { error make {msg: $"($pair.0): want one of ($option_names | columns | str join ', ')"} }
        let saved = ^$dot set $"desktop/quickshell.($option)" $pair.1 --no-system | complete
        if $saved.exit_code != 0 {
            notify "Pomodoro" $"Could not save ($pair.0): ($saved.stderr | str trim | lines | last 1 | str join)"
            exit 1
        }
    }
    retime
}

# a running timer takes the new lengths: the current phase keeps its elapsed time against its new length
def retime []: nothing -> nothing {
    let state = state-load
    if not $state.running { return }
    let config = config-load
    let lengths = {work: $config.focus, break: $config.break, long: $config.long, cycles: $config.cycles}
    let total = ($state | get $state.phase) * 60
    let left = if $state.paused { $state.remaining } else { [($state.endsAt - (now)) 0] | math max }
    let left = ($lengths | get $state.phase) * 60 - ($total - $left)
    let state = $state | merge $lengths
    if $left <= 0 {
        state-save $state
        phase-advance
    } else if $state.paused {
        state-save ($state | merge {remaining: $left})
    } else {
        phase-start $state $state.phase $left
    }
}

def "main status" [--json (-j)]: nothing -> nothing {
    let state = state-load
    let config = config-load
    let status = if not $state.running {
        {
            running: false, paused: false, phase: idle, label: Pomodoro, remainingSeconds: 0, remaining: "", cycle: 0,
            totalSeconds: 0, defaultWork: $config.focus, longEvery: $config.cycles, tooltip: "Pomodoro: off"
        }
    } else {
        let remaining = [(if $state.paused { $state.remaining } else { $state.endsAt - (now) }) 0] | math max
        let label = $phase_labels | get $state.phase
        let paused_note = if $state.paused { " (paused)" } else { "" }
        {
            running: true, paused: $state.paused, phase: $state.phase, label: $label, remainingSeconds: $remaining,
            remaining: (clock $remaining), cycle: $state.cycle,
            totalSeconds: (($state | get $state.phase) * 60),
            longEvery: ($state.cycles? | default $config.cycles),
            tooltip: $"($label) :: (clock $remaining) left :: pomodoro ($state.cycle)($paused_note)"
        }
    }
    print (if $json { $status | to json -r } else { $status.tooltip })
}

def main []: nothing -> nothing { main status }
