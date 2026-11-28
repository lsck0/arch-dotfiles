#!/usr/bin/env -S nu --no-config-file
# a cli call with no app running starts one in the foreground, so the cli waits in a job for the app started here

const REPO = path self | path expand | path dirname --num-levels 5
use ($REPO | path join scripts lib state.nu) [xdg]
use ($REPO | path join scripts lib proc.nu) [notify]

const OBSIDIAN = "/usr/bin/obsidian"
const WAIT_TRIES = 60
const CLI_TIMEOUT = "10"

def instance-running []: nothing -> bool {
    let lock = xdg config obsidian SingletonLock
    let target = try { ^readlink $lock | str trim } catch { "" }
    $target != "" and ($"/proc/($target | split row "-" | last)" | path exists)
}

def restrict-state []: nothing -> string {
    ^timeout $CLI_TIMEOUT $OBSIDIAN plugins:restrict | complete | get stdout | str trim
}

# Ends with the app: the job dies with this process, and a second launch returns at once beside a first that did it.
def restrict-disable []: nothing -> nothing {
    mut state = ""
    for _ in 1..$WAIT_TRIES {
        if (instance-running) {
            $state = restrict-state
            if $state in [on off] { break }
        }
        sleep 1sec
    }
    if $state != on { return }
    let off = ^timeout $CLI_TIMEOUT $OBSIDIAN plugins:restrict off | complete
    if $off.exit_code != 0 {
        let reason = $off.stderr | str trim | default --empty $"exit ($off.exit_code)"
        notify obsidian "Obsidian kept restricted mode on" $"Community plugins stay off: ($reason)" | ignore
    }
}

def --wrapped main [...args: string]: nothing -> nothing {
    if ($args | get --optional 0) in ["-h" "--help"] {
        print "usage: obsidian-launch [args...]: start obsidian with restricted mode off, so its community plugins load"
        return
    }
    job spawn { restrict-disable } | ignore
    ^$OBSIDIAN ...$args
}
