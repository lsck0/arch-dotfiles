#!/usr/bin/env -S nu --no-config-file
# a sleep inhibitor while an ssh login session is open; locking still happens

const RECHECK = 60sec
const ENDED = "ended"
const TIMEOUT = "timeout"

# logind sessions, not tcp sockets on the port: a preauth connection is no session, and a closing session no longer counts
def ssh-session-open []: nothing -> bool {
    ^loginctl list-sessions --no-legend | lines | each { str trim | split row --regex '\s+' | first } | any {|id|
        let props = ^loginctl show-session $id -p Service -p State | lines | parse "{key}={value}" | transpose -r -d
        $props.Service? == sshd and $props.State? != closing
    }
}

def main [] {
    # any logind signal or the recheck timeout triggers a check; gdbus's startup lines give the initial one
    job spawn {
        ^gdbus monitor --system --dest org.freedesktop.login1 | lines | each { job send 0 } | ignore
        $ENDED | job send 0
    }
    mut holder: any = null
    while (try { job recv --timeout $RECHECK } catch { $TIMEOUT }) != $ENDED {
        if (ssh-session-open) {
            if $holder == null {
                $holder = job spawn { ^systemd-inhibit --what=sleep --mode=block --who=sshd --why="ssh session" sleep infinity }
            }
        } else if $holder != null {
            job kill $holder
            $holder = null
        }
    }
    # the monitor ending is a failure, so Restart=on-failure brings the guard back
    error make {msg: "gdbus monitor ended"}
}
