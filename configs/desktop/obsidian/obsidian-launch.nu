#!/usr/bin/env -S nu --no-config-file
# restricted mode lives in obsidian's localstorage, not the vault, so the running app's cli lifts it; a cli call with
# no app running starts one in the foreground instead, so it waits for the app first

const OBSIDIAN = "/usr/bin/obsidian"
const WAIT_TRIES = 60
const CLI_TIMEOUT = "10"

def instance-running []: nothing -> bool {
    let lock = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join obsidian SingletonLock
    # the lock links to <host>-<pid> while an instance runs
    let target = try { ^readlink $lock | str trim } catch { "" }
    $target != "" and ($"/proc/($target | split row "-" | last)" | path exists)
}

def restrict-state []: nothing -> string {
    ^timeout $CLI_TIMEOUT $OBSIDIAN plugins:restrict | complete | get stdout | str trim
}

def --wrapped main [...args: string]: nothing -> nothing {
    let app = job spawn { ^$OBSIDIAN ...$args }
    mut state = ""
    for _ in 1..$WAIT_TRIES {
        if (instance-running) {
            $state = restrict-state
            if $state in [on off] { break }
        }
        sleep 1sec
    }
    if $state == on { ^$OBSIDIAN plugins:restrict off | ignore }
    while $app in (job list | get id) { sleep 1sec }
}
