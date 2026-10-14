#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run state-file]

const INHIBIT = [systemd-inhibit --what=sleep:idle --who=toggles "--why=keep-awake toggle enabled" --mode=block sleep infinity]

# the recorded pid, only while it is still our inhibitor and not a reused one
def inhibitor-pid []: nothing -> any {
    let pid = try { open --raw (state-file keep-awake.pid --volatile) | str trim | into int }
    if (try { open --raw $"/proc/($pid)/comm" | str trim }) == systemd-inhibit { $pid }
}

def main [action: string = "toggle"] {
    switch-run {
        label: "Keep Awake"
        is-on: {|| inhibitor-pid | is-not-empty }
        # nu cannot leave a child running past its own exit, sh's & can and hands back the pid
        on: {|| ^sh -c '"$@" > /dev/null 2>&1 & echo $!' sh ...$INHIBIT | str trim | save --force (state-file keep-awake.pid --volatile) }
        off: {||
            try { kill (inhibitor-pid) }
            rm --force (state-file keep-awake.pid --volatile)
        }
    } $action
}
