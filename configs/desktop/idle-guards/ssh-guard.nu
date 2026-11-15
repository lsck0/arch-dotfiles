#!/usr/bin/env -S nu --no-config-file
# a sleep inhibitor while an ssh login session is open; locking still happens

# logind signals no session going to closing (its login gone, a process left behind), so an open one is re-read
const RECHECK = 60sec
# a session coming or going, and gdbus's line once it listens, which starts the first check
const SESSION_EVENT = 'SessionNew|SessionRemoved|is owned by'
const ENDED = "ended"
const TIMEOUT = "timeout"

# Logind sessions, not sockets on the port: a preauth connection is no session, a closing one no longer counts.
def ssh-session-open []: nothing -> bool {
    ^loginctl list-sessions --no-legend | lines | each { str trim | split row --regex '\s+' | first } | any {|id|
        # a short login is often gone again before its show-session, which loginctl logs as an error
        let shown = ^loginctl show-session $id -p Service -p State | complete
        if $shown.exit_code != 0 { return false }
        let props = $shown.stdout | lines | parse "{key}={value}" | transpose -r -d
        $props.Service? == sshd and $props.State? != closing
    }
}

def main [] {
    job spawn {
        ^gdbus monitor --system --dest org.freedesktop.login1 | lines | where $it =~ $SESSION_EVENT | each { job send 0 } | ignore
        $ENDED | job send 0
    }
    mut holder: any = null
    # no session, no wakeup: the recheck runs only while the inhibitor is held
    while (if $holder == null { job recv } else { try { job recv --timeout $RECHECK } catch { $TIMEOUT } }) != $ENDED {
        if (ssh-session-open) {
            if $holder == null {
                $holder = job spawn { ^systemd-inhibit --what=sleep --mode=block --who=sshd --why="ssh session" sleep infinity }
            }
        } else if $holder != null {
            job kill $holder
            $holder = null
        }
    }
    # a failure, so Restart=on-failure brings the guard back
    error make {msg: "gdbus monitor ended"}
}
