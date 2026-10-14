#!/usr/bin/env -S nu --no-config-file --stdin
# keeps the machine awake while a coding agent (claude code, hermes) actually works: a turn in flight or a subagent
# running. an open but idle session holds nothing. called from the agents' hooks with their json on stdin

const POLL = 5sec
const SESSION_DEFAULT = "default"

def state-dir []: nothing -> path {
    let dir = $env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u | str trim)" | path join agent-busy
    mkdir $dir
    $dir
}

def alive [pid: string]: nothing -> bool {
    $pid != "" and ($"/proc/($pid)" | path exists)
}

def read-or [file: path, fallback: string]: nothing -> string {
    if ($file | path exists) { open --raw $file | str trim } else { $fallback }
}

def session-id []: string -> string {
    let payload = $in
    try { $payload | from json | get session_id } catch { $SESSION_DEFAULT } | default $SESSION_DEFAULT
}

# the hook's caller, the agent process: its exit ends the session's claim
def parent-pid []: nothing -> string {
    open --raw $"/proc/($nu.pid)/stat" | str replace --regex '^.*\) ' '' | split row " " | get 1
}

# busy while its turn flag exists or a subagent count is above zero, and its agent process lives
def session-busy [dir: path, sid: string]: nothing -> bool {
    if not (alive (read-or ($dir | path join $"($sid).pid") "")) { return false }
    ($dir | path join $"($sid).turn" | path exists) or ((read-or ($dir | path join $"($sid).agents") "0" | into int) > 0)
}

def any-busy [dir: path]: nothing -> bool {
    glob ($dir | path join "*.pid") | any {|f| session-busy $dir ($f | path parse | get stem) }
}

# one block inhibitor for all agents; it exits by itself once nothing is busy, so a crash never leaks it
def holder-ensure [dir: path]: nothing -> nothing {
    if (alive (read-or ($dir | path join .holder) "")) { return }
    (^setsid --fork systemd-inhibit --what=sleep:handle-lid-switch --who="coding agent" --why="agent working" --mode=block
        $env.CURRENT_FILE hold) out+err> /dev/null
}

def agents-add [dir: path, sid: string, delta: int]: nothing -> nothing {
    let file = $dir | path join $"($sid).agents"
    [((read-or $file "0" | into int) + $delta) 0] | math max | into string | save --force $file
}

def start [stdin: string, subagent: bool]: nothing -> nothing {
    let dir = state-dir
    let sid = $stdin | session-id
    parent-pid | save --force ($dir | path join $"($sid).pid")
    if $subagent { agents-add $dir $sid 1 } else { touch ($dir | path join $"($sid).turn") }
    holder-ensure $dir
}

def "main turn-start" []: string -> nothing { start $in false }
def "main subagent-start" []: string -> nothing { start $in true }
def "main turn-end" []: string -> nothing {
    let sid = $in | session-id
    rm --force (state-dir | path join $"($sid).turn")
}

def "main subagent-stop" []: string -> nothing {
    let sid = $in | session-id
    agents-add (state-dir) $sid (-1)
}

# exit 0 while any agent works (hypridle's condition)
def "main busy" []: nothing -> nothing { if not (any-busy (state-dir)) { exit 1 } }

# the inhibitor's child, holding the block while anything is busy
def "main hold" []: nothing -> nothing {
    let dir = state-dir
    $nu.pid | into string | save --force ($dir | path join .holder)
    while (any-busy $dir) { sleep $POLL }
}

def main []: nothing -> nothing {
    print --stderr "usage: agent-guard turn-start|turn-end|subagent-start|subagent-stop|busy"
    exit 2
}
