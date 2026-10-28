#!/usr/bin/env -S nu --no-config-file

const unit_prefix = "quickshell-reminder-"
const bell_glyph = "\u{f009e}"
const list_glyph = "\u{f088c}"
const shell_config = ($nu.home-dir | path join .config quickshell)
const alert = ($shell_config | path join scripts alert.nu)

def reminder-dir []: nothing -> path { $env.XDG_RUNTIME_DIR | path join quickshell-reminders }

# Sent as the app the shell shows through dnd and keeps out of history (NotificationLogic.js ACTION_APP).
def notify [glyph: string, title: string, body: string = ""]: nothing -> nothing {
    ^notify-send -a quickshell-action -u low -h $"string:lsck0-glyph:($glyph)" -- $title $body
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
    let now = date now | into int | $in // 1_000_000_000
    systemctl --user list-timers --all --output=json $"($unit_prefix)*.timer" | from json
    | each {|timer| {timer: $timer.unit, at: (($timer.next | default 0) // 1_000_000)} }
    | where at > $now
    | each {|timer|
        let unit = $timer.timer | str replace -r '\.timer$' ''
        let minutes = $unit | parse $"($unit_prefix){minutes}m-{set_at}" | get 0.minutes | into int
        let message_path = reminder-dir | path join $"($unit).message"
        let message = if ($message_path | path exists) { open --raw $message_path } else { "" }
        {
            unit: $unit, timer: $timer.timer, minutes: $minutes, message: $message,
            label: (if $message != "" { $message } else { $"($minutes)-min reminder" }),
            remaining: (remaining-format ($timer.at - $now)), remainingSeconds: ($timer.at - $now), at: $timer.at,
            atTime: ($timer.at * 1_000_000_000 | into datetime | date to-timezone local | format date "%-H:%M")
        }
    }
}

def reminder-json []: nothing -> record {
    let reminders = reminder-list
    let count = $reminders | length
    let tooltip = match $count { 0 => "Set Reminder", 1 => "1 reminder", _ => $"($count) reminders" }
    {count: $count, active: ($count > 0), tooltip: $tooltip, reminders: $reminders}
}

def index-write []: nothing -> nothing {
    mkdir (reminder-dir)
    let index = reminder-dir | path join index.json
    reminder-json | to json -r | save -f $"($index).tmp"
    mv -f $"($index).tmp" $index
}

def main [
    --interactive (-i)
    minutes?: int
    ...message: string
]: nothing -> nothing {
    if $interactive {
        ^timeout 3 quickshell ipc -p $shell_config call shell summon panel.reminders "{}"
        return
    }
    if $minutes == null or $minutes <= 0 { error make {msg: "minutes must be a positive integer, see --help"} }
    let message = $message | str join " "
    let unit_label = if $minutes == 1 { "1 minute" } else { $"($minutes) minutes" }
    # nanoseconds: two reminders of the same length set in one second would share a unit
    let unit = $"($unit_prefix)($minutes)m-(date now | into int)"
    mkdir (reminder-dir)
    if $message != "" { $message | save -f (reminder-dir | path join $"($unit).message") }
    systemd-run --user --quiet --collect $"--on-active=($minutes)m" $"--unit=($unit)" ($env.CURRENT_FILE | path expand) _fire $unit
    index-write
    let title = if $message != "" { $"($message) in ($unit_label)" } else { $"Reminder set for ($unit_label)" }
    notify $bell_glyph $title $"Due at (date now | $in + ($minutes * 1min) | format date '%-H:%M')"
}

def "main show" [--json (-j)]: nothing -> nothing {
    if $json { print (reminder-json | to json -r); return }
    let lines = reminder-list | each { $"($in.label) in ($in.remaining) \(($in.atTime)\)" }
    notify $list_glyph "Upcoming reminders" (if ($lines | is-empty) { "None" } else { $lines | str join "\n" })
}

def "main list" [--json (-j)]: nothing -> nothing { main show --json=$json }

def "main cancel" [target: string]: nothing -> nothing {
    let unit = $target | str replace -r '\.(timer|service)$' ''
    if not ($unit starts-with $unit_prefix) { error make {msg: $"refusing to cancel non-reminder unit '($target)'"} }
    systemctl --user stop $"($unit).timer" $"($unit).service" | complete | ignore
    rm -f (reminder-dir | path join $"($unit).message")
    index-write
}

def "main delete" [target: string]: nothing -> nothing { main cancel $target }

# name a pending reminder, or with no name drop it back to "<n>-min reminder"
def "main rename" [target: string, ...name: string]: nothing -> nothing {
    let unit = $target | str replace -r '\.(timer|service)$' ''
    if not ($unit starts-with $unit_prefix) { error make {msg: $"refusing to rename non-reminder unit '($target)'"} }
    if $unit not-in (reminder-list | get unit) { error make {msg: $"no pending reminder ($unit)"} }
    let name = $name | str join " " | str trim
    let message_path = reminder-dir | path join $"($unit).message"
    if $name == "" { rm -f $message_path } else { $name | save -f $message_path }
    index-write
}

def "main clear" []: nothing -> nothing {
    let units = systemctl --user list-timers --all --output=json $"($unit_prefix)*.timer" | from json
    if ($units | is-not-empty) { systemctl --user stop ...($units | each { [$in.unit $in.activates] } | flatten) }
    rm -f ...(glob (reminder-dir | path join $"($unit_prefix)*.message"))
    index-write
    notify $list_glyph "Reminders cleared"
}

# the timer's own command: alert.nu so an elapsed reminder does not auto-expire, then drop it from the index
def "main _fire" [unit: string]: nothing -> nothing {
    let message_path = reminder-dir | path join $"($unit).message"
    let message = if ($message_path | path exists) { open --raw $message_path } else { "" }
    let minutes = $unit | parse $"($unit_prefix){minutes}m-{set_at}" | get 0.minutes
    let title = if $message != "" { $message } else { "Time's up" }
    ^$alert $title $"($minutes) minute reminder" $bell_glyph reminder $message
    rm -f $message_path
    index-write
}
