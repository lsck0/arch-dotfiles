#!/usr/bin/env -S nu --no-config-file

const HERE = path self | path expand | path dirname
use ($HERE | path join lib shell.nu) [SHELL_CONFIG action-notify shell-call]

const UNIT_PREFIX = "quickshell-reminder-"
const BELL_GLYPH = "\u{f009e}"
const LIST_GLYPH = "\u{f088c}"
const ALERT = ($SHELL_CONFIG | path join scripts alert.nu)
# a time rearm finds already past fires this long after it, once the shell that shows the card is up
const MISSED_DELAY_S = 30
# a calendar time this close to now could pass before systemd-run arms it
const ARM_MARGIN_S = 2

# the index TimerState.qml watches; gone on reboot, rebuilt from the records
def reminder-dir []: nothing -> path { $env.XDG_RUNTIME_DIR | path join quickshell-reminders }

# one {unit, at, message, clock} per pending reminder, kept across a reboot so rearm can bring it back
def record-dir []: nothing -> path {
    $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state) | path join quickshell reminders
}

def record-path [unit: string]: nothing -> path { record-dir | path join $"($unit).json" }

def record-load [unit: string]: nothing -> record {
    let path = record-path $unit
    {unit: $unit, at: 0, message: "", clock: false} | merge (if ($path | path exists) { open $path } else { {} })
}

def record-save [record: record]: nothing -> nothing {
    mkdir (record-dir)
    let path = record-path $record.unit
    $record | to json -r | save -f $"($path).tmp"
    mv -f $"($path).tmp" $path
}

def epoch-now []: nothing -> int { date now | into int | $in // 1_000_000_000 }

def epoch-to-date [epoch: int]: nothing -> datetime { $epoch * 1_000_000_000 | into datetime | date to-timezone local }

def epoch-format-time [epoch: int]: nothing -> string {
    let at = epoch-to-date $epoch
    $at | format date (if ($at | format date '%F') == (date now | format date '%F') { '%-H:%M' } else { '%a %-d %b %-H:%M' })
}

# TimerState.qml's remainingText mirrors it: keep the two in sync.
def remaining-format [seconds: int]: nothing -> string {
    if $seconds >= 86400 {
        let days = $seconds // 86400
        let hours = ($seconds mod 86400) // 3600
        if $hours > 0 { $"($days)d ($hours)h" } else { $"($days)d" }
    } else if $seconds >= 3600 {
        let hours = $seconds // 3600
        let minutes = ($seconds mod 3600) // 60
        if $minutes > 0 { $"($hours)h ($minutes)m" } else { $"($hours)h" }
    } else {
        let minutes = $seconds // 60
        let rest = $seconds mod 60
        if $minutes > 0 and $rest > 0 { $"($minutes)m ($rest)s" } else if $minutes > 0 { $"($minutes)m" } else { $"($rest)s" }
    }
}

def reminder-list []: nothing -> table {
    let now = epoch-now
    systemctl --user list-timers --all --output=json $"($UNIT_PREFIX)*.timer" | from json
    | each {|timer| {timer: $timer.unit, at: (($timer.next | default 0) // 1_000_000)} }
    | where at > $now
    | each {|timer|
        let unit = $timer.timer | str replace -r '\.timer$' ''
        let minutes = $unit | parse $"($UNIT_PREFIX){minutes}m-{set_at}" | get 0.minutes | into int
        let record = record-load $unit
        let at_time = epoch-to-date $timer.at | format date "%-H:%M"
        let label = if $record.message != "" { $record.message } else if $record.clock { $"reminder at ($at_time)" } else {
            $"($minutes)-min reminder"
        }
        {
            unit: $unit, timer: $timer.timer, minutes: $minutes, message: $record.message, label: $label,
            remaining: (remaining-format ($timer.at - $now)), remainingSeconds: ($timer.at - $now), at: $timer.at,
            atTime: $at_time
        }
    }
}

def reminder-json []: nothing -> record {
    {reminders: (reminder-list)}
}

def index-write []: nothing -> nothing {
    mkdir (reminder-dir)
    let index = reminder-dir | path join index.json
    reminder-json | to json -r | save -f $"($index).tmp"
    mv -f $"($index).tmp" $index
}

# wall-clock, so a suspend neither delays it nor drops it: a time passed while asleep fires on resume; in UTC, so a dst
# change or a new timezone keeps the epoch in the record
def timer-arm [unit: string, at: int]: nothing -> record {
    let calendar = $at * 1_000_000_000 | into datetime | format date '%Y-%m-%d %H:%M:%S UTC'
    (systemd-run --user --quiet --collect $"--on-calendar=($calendar)" --timer-property=AccuracySec=1s $"--unit=($unit)"
        ($env.CURRENT_FILE | path expand) _fire $unit) | complete
}

# the minutes in the unit name are reminder-list's "<n>-min reminder" label; --clock: set for a time of day, labelled by it
def reminder-set [at: int, message: string, --clock]: nothing -> nothing {
    let minutes = [1 ((($at - (epoch-now)) / 60) | math round)] | math max
    # nanoseconds: two reminders of the same length set in one second would share a unit
    let unit = $"($UNIT_PREFIX)($minutes)m-(date now | into int)"
    record-save {unit: $unit, at: $at, message: $message, clock: $clock}
    let armed = timer-arm $unit $at
    if $armed.exit_code != 0 {
        rm -f (record-path $unit)
        action-notify $BELL_GLYPH "Reminder not set" ($armed.stderr | str trim)
        exit 1
    }
    index-write
}

def main [
    --interactive (-i)
    minutes?: int
    ...message: string
]: nothing -> nothing {
    if $interactive {
        shell-call shell summon panel.reminders "{}"
        return
    }
    if $minutes == null or $minutes <= 0 { error make {msg: "minutes must be a positive integer, see --help"} }
    let message = $message | str join " "
    let at = (epoch-now) + $minutes * 60
    reminder-set $at $message
    let unit_label = if $minutes == 1 { "1 minute" } else { $"($minutes) minutes" }
    let title = if $message != "" { $"($message) in ($unit_label)" } else { $"Reminder set for ($unit_label)" }
    action-notify $BELL_GLYPH $title $"Due at (epoch-format-time $at)"
}

# at a wall-clock time, seconds since the epoch
def "main at" [epoch: int, ...message: string]: nothing -> nothing {
    let now = epoch-now
    if $epoch <= $now + $ARM_MARGIN_S { error make {msg: $"($epoch) is not in the future"} }
    let message = $message | str join " "
    reminder-set $epoch $message --clock
    let time = epoch-format-time $epoch
    let title = if $message != "" { $"($message) at ($time)" } else { $"Reminder set for ($time)" }
    action-notify $BELL_GLYPH $title $"Due in (remaining-format ($epoch - $now))"
}

def "main show" [--json (-j)]: nothing -> nothing {
    if $json { print (reminder-json | to json -r); return }
    let lines = reminder-list | each { $"($in.label) in ($in.remaining) \(($in.atTime)\)" }
    action-notify $LIST_GLYPH "Upcoming reminders" (if ($lines | is-empty) { "None" } else { $lines | str join "\n" })
}

def "main list" [--json (-j)]: nothing -> nothing { main show --json=$json }

def "main cancel" [target: string]: nothing -> nothing {
    let unit = $target | str replace -r '\.(timer|service)$' ''
    if not ($unit starts-with $UNIT_PREFIX) { error make {msg: $"refusing to cancel non-reminder unit '($target)'"} }
    if $unit not-in (reminder-list | get unit) { error make {msg: $"no pending reminder ($unit)"} }
    systemctl --user stop $"($unit).timer" $"($unit).service" | complete | ignore
    rm -f (record-path $unit)
    index-write
}

def "main delete" [target: string]: nothing -> nothing { main cancel $target }

# name a pending reminder, or with no name drop it back to "<n>-min reminder"
def "main rename" [target: string, ...name: string]: nothing -> nothing {
    let unit = $target | str replace -r '\.(timer|service)$' ''
    if not ($unit starts-with $UNIT_PREFIX) { error make {msg: $"refusing to rename non-reminder unit '($target)'"} }
    let pending = reminder-list | where unit == $unit | get --optional 0
    if $pending == null { error make {msg: $"no pending reminder ($unit)"} }
    record-save (record-load $unit | merge {at: $pending.at, message: ($name | str join " " | str trim)})
    index-write
}

def "main clear" []: nothing -> nothing {
    let units = systemctl --user list-timers --all --output=json $"($UNIT_PREFIX)*.timer" | from json
    if ($units | is-not-empty) { systemctl --user stop ...($units | each { [$in.unit $in.activates] } | flatten) }
    rm -f ...(glob (record-dir | path join $"($UNIT_PREFIX)*.json"))
    index-write
    action-notify $LIST_GLYPH "Reminders cleared"
}

# the timer's own command: alert.nu so an elapsed reminder does not auto-expire, then drop it from the index
def "main _fire" [unit: string]: nothing -> nothing {
    let record = record-load $unit
    let minutes = $unit | parse $"($UNIT_PREFIX){minutes}m-{set_at}" | get 0.minutes
    let title = if $record.message != "" { $record.message } else { "Time's up" }
    let body = if ($record.missed? | default false) { $"missed at (epoch-format-time $record.at)" } else if $record.clock {
        $"reminder for (epoch-format-time $record.at)"
    } else { $"($minutes) minute reminder" }
    ^$ALERT $title $body $BELL_GLYPH reminder $record.message
    rm -f (record-path $unit)
    index-write
}

# once a session (quickshell-reminders-rearm.service): a reboot or logout took the timers, the records survived
def "main rearm" []: nothing -> nothing {
    let now = epoch-now
    for path in (glob (record-dir | path join $"($UNIT_PREFIX)*.json")) {
        let record = record-load ($path | path parse | get stem)
        if (systemctl --user is-active --quiet $"($record.unit).timer" | complete | get exit_code) == 0 { continue }
        let missed = $record.at <= $now + $ARM_MARGIN_S
        if $missed { record-save ($record | merge {missed: true}) }
        let armed = timer-arm $record.unit (if $missed { $now + $MISSED_DELAY_S } else { $record.at })
        if $armed.exit_code != 0 {
            let label = if $record.message != "" { $record.message } else { $"reminder at (epoch-format-time $record.at)" }
            action-notify $BELL_GLYPH "Reminder not restored" $"($label)\n($armed.stderr | str trim)"
        }
    }
    index-write
}
