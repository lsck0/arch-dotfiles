#!/usr/bin/env -S nu --no-config-file --stdin
# keeps the machine awake while a coding agent has a turn or subagent in flight; called from the agents' hooks

const POLL = 5sec
const SESSION_DEFAULT = "default"
const SHELLS = [sh bash dash zsh]
const INHIBIT_SLEEP = "sleep"
const INHIBIT_LID = "handle-lid-switch"
const BATTERY_DISCHARGING = "Discharging"
# logind drops an inhibitor when its process is gone, a moment after the kill
const RELEASE_SETTLE = 500ms
# every hook of a working agent, a subagent's tool calls included, rewrites the claim; a subagent count whose claim is
# older than this lost its stop hook (an interrupt, a crash) and would otherwise hold the machine up for good
const AGENTS_TTL = 30min

def state-dir []: nothing -> path {
    let dir = $env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u | str trim)" | path join agent-busy
    mkdir $dir
    $dir
}

def stat-fields [pid: string]: nothing -> list<string> {
    open --raw $"/proc/($pid)/stat" | str replace --regex '^.*\) ' '' | split row " "
}

# A process claim, "<pid> <start time>": a pid alone outlives its process once the kernel reuses it.
export def claim-of [pid: string]: nothing -> string {
    $"($pid) (stat-fields $pid | get 19)"
}

def alive [claim: string]: nothing -> bool {
    let pid = $claim | split row " " | first
    $pid != "" and (try { (claim-of $pid) == $claim } catch { false })
}

def read-or [file: path, fallback: string]: nothing -> string {
    if ($file | path exists) { open --raw $file | str trim } else { $fallback }
}

def session-id []: string -> string {
    let payload = $in
    let sid = try { $payload | from json | get session_id } catch { $SESSION_DEFAULT } | default $SESSION_DEFAULT
    # the id becomes a state-file name; a '/' would escape the state dir, so reject it
    if ($sid | str contains "/") { $SESSION_DEFAULT } else { $sid }
}

def ppid-of [pid: string]: nothing -> string {
    stat-fields $pid | get 1
}

# The hook's caller, the agent process: its exit ends the session's claim. Agents run a hook through `bash -c`, which
# usually execs it; a shell that stayed in between exits with the hook, so the claim goes past it.
def parent-pid []: nothing -> string {
    mut pid = ppid-of ($nu.pid | into string)
    while $pid != "1" and (open --raw $"/proc/($pid)/comm" | str trim) in $SHELLS { $pid = ppid-of $pid }
    $pid
}

export def session-busy [dir: path, sid: string]: nothing -> bool {
    let pid_file = $dir | path join $"($sid).pid"
    let agents_file = $dir | path join $"($sid).agents"
    let claim = read-or $pid_file ""
    if not (alive $claim) {
        # a dead session's turn or subagent count would come back with its claim
        if (read-or $pid_file "") == $claim { rm --force $pid_file ($dir | path join $"($sid).turn") $agents_file }
        return false
    }
    if ((date now) - (ls $pid_file).0.modified) > $AGENTS_TTL { rm --force $agents_file }
    ($dir | path join $"($sid).turn" | path exists) or ((read-or $agents_file "0" | into int) > 0)
}

def any-busy [dir: path]: nothing -> bool {
    glob ($dir | path join "*.pid") | any {|f| session-busy $dir ($f | path parse | get stem) }
}

def on-battery []: nothing -> bool {
    glob /sys/class/power_supply/BAT*/status | any { (open --raw $in | str trim) == $BATTERY_DISCHARGING }
}

def lid-closed []: nothing -> bool {
    glob /proc/acpi/button/lid/*/state | any { open --raw $in | str contains closed }
}

def docked []: nothing -> bool {
    (^busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager Docked | complete).stdout
        | str contains "true"
}

def power-read []: nothing -> record<on_battery: bool, lid_closed: bool, docked: bool> {
    let on_battery = on-battery
    let lid_closed = $on_battery and (lid-closed)
    {on_battery: $on_battery, lid_closed: $lid_closed, docked: ($lid_closed and (docked))}
}

# The inhibitors a working agent holds: on mains the machine stays up through an idle timeout and a closed lid; on
# battery only through the idle timeout, and a closed, undocked notebook holds nothing, so it suspends.
export def inhibits-wanted [power: record<on_battery: bool, lid_closed: bool, docked: bool>]: nothing -> list<string> {
    if not $power.on_battery { return [$INHIBIT_SLEEP $INHIBIT_LID] }
    if $power.lid_closed and not $power.docked { return [] }
    [$INHIBIT_SLEEP]
}

# An inhibitor that ends with the holder, so a killed holder never leaks it.
def inhibit-spawn [what: string]: nothing -> int {
    let holder = $nu.pid
    job spawn {
        (^systemd-inhibit $"--what=($what)" --who="coding agent" --why="agent working" --mode=block
            tail $"--pid=($holder)" --follow /dev/null)
    }
}

# One holder for all agents; it exits by itself once nothing is busy.
def holder-ensure [dir: path]: nothing -> nothing {
    if (alive (read-or ($dir | path join .holder) "")) { return }
    ^setsid --fork $env.CURRENT_FILE hold out+err> /dev/null
}

# Parallel subagent hooks would lose counts in an unlocked read-modify-write.
def agents-add [dir: path, sid: string, delta: int]: nothing -> nothing {
    ^flock ($dir | path join .agents.lock) $nu.current-exe --no-config-file $env.CURRENT_FILE agents-add-locked $sid $"($delta)"
}

def start [stdin: string, subagent: bool]: nothing -> nothing {
    let dir = state-dir
    let sid = $stdin | session-id
    claim-of (parent-pid) | save --force ($dir | path join $"($sid).pid")
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

# Exits 0 while an agent works and may keep the machine up (hypridle's condition).
def "main busy" []: nothing -> nothing {
    if not (any-busy (state-dir)) or (inhibits-wanted (power-read) | is-empty) { exit 1 }
}

def "main agents-add-locked" [sid: string, delta: int]: nothing -> nothing {
    let file = state-dir | path join $"($sid).agents"
    [((read-or $file "0" | into int) + $delta) 0] | math max | into string | save --force $file
}

def "main hold" []: nothing -> nothing {
    let dir = state-dir
    claim-of ($nu.pid | into string) | save --force ($dir | path join .holder)
    mut held = {}
    while (any-busy $dir) {
        let wanted = inhibits-wanted (power-read)
        let before = $held
        for what in ($before | columns | where $it not-in $wanted) {
            job kill ($before | get $what)
            $held = $held | reject $what
        }
        for what in ($wanted | where $it not-in ($before | columns)) { $held = $held | insert $what (inhibit-spawn $what) }
        # the lid closed on mains and the charger then pulled: logind acted on the lid long ago, so the suspend is asked here
        if $INHIBIT_LID in $before and ($wanted | is-empty) {
            sleep $RELEASE_SETTLE
            ^systemctl suspend | complete | ignore
        }
        sleep $POLL
    }
}

def main []: nothing -> nothing {
    print --stderr "usage: agent-guard turn-start|turn-end|subagent-start|subagent-stop|busy"
    exit 2
}
