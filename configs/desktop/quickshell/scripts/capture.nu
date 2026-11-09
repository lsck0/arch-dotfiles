#!/usr/bin/env -S nu --no-config-file
# Quick capture from the launcher (+ task, ! reminder, # note): one line in, a confirmation out.

const INBOX = "sync/notes/inbox.md"
const TASK_GLYPH = "\u{f0ae}"
const NOTE_GLYPH = "\u{f0f6}"

def notify [glyph: string, title: string, body: string = ""]: nothing -> nothing {
    ^notify-send -a quickshell-action -u low -h $"string:lsck0-glyph:($glyph)" -- $title $body
}

# taskwarrior parses project:, due:, scheduled:, priority:, +tag itself; each word stays one argument
def "main task" [...words: string]: nothing -> nothing {
    if ($words | is-empty) { error make {msg: "nothing to add"} }
    let r = ^task rc.confirmation=no rc.verbose=new-id add ...$words | complete
    if $r.exit_code != 0 {
        notify $TASK_GLYPH "Task not added" ($r.stderr | str trim)
        exit 1
    }
    notify $TASK_GLYPH ($r.stdout | str trim) ($words | str join " ")
}

# 90, 10m, 2h, 1h30m: whole minutes, null when it is not a duration
export def minutes-of [text: string]: nothing -> any {
    let m = $text | parse --regex '^(?:(?<h>\d+)h)?(?:(?<m>\d+)m?)?$' | get --optional 0
    # an unmatched optional group reads as null or empty depending on the nu version
    let h = $m.h? | default ""
    let mm = $m.m? | default ""
    if $h == "" and $mm == "" { return null }
    let hours = if $h == "" { 0 } else { $h | into int }
    let minutes = if $mm == "" { 0 } else { $mm | into int }
    let total = $hours * 60 + $minutes
    if $total > 0 { $total } else { null }
}

def "main remind" [duration: string, ...message: string]: nothing -> nothing {
    let minutes = minutes-of $duration
    if $minutes == null { error make {msg: $"not a duration: ($duration) \(90, 10m, 2h, 1h30m\)"} }
    ^($env.CURRENT_FILE | path expand | path dirname | path join reminder.nu) $minutes ...$message
}

# one dated heading per day, newest entries at the bottom; nvim and the agents read it as plain markdown
def "main note" [...words: string]: nothing -> nothing {
    if ($words | is-empty) { error make {msg: "nothing to note"} }
    let inbox = $nu.home-dir | path join $INBOX
    mkdir ($inbox | path dirname)
    let heading = $"## (date now | format date '%Y-%m-%d')"
    let has_heading = ($inbox | path exists) and (open --raw $inbox | lines | any { $in == $heading })
    let prefix = if $has_heading { "" } else if ($inbox | path exists) { $"\n($heading)\n\n" } else { $"# Inbox\n\n($heading)\n\n" }
    $"($prefix)- (date now | format date '%H:%M') ($words | str join ' ')\n" | save --append $inbox
    notify $NOTE_GLYPH "Noted" ($words | str join " ")
}

def main []: nothing -> nothing {
    print "capture task <words> | remind <90|10m|2h|1h30m> <message> | note <words>"
}
