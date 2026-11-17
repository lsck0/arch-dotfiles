#!/usr/bin/env -S nu --no-config-file
# a sleep inhibitor while media plays, a microphone records or an ssh login session is open; dim and lock still happen

# logind signals no session going to closing (its login gone, a process left behind), so an open one is re-read
const SSH_RECHECK = 60sec
# a session coming or going, and gdbus's line once it listens, which starts the first check
const SESSION_EVENT = 'SessionNew|SessionRemoved|is owned by'
const ENDED = "ended"
const TIMEOUT = "timeout"
# a source's own events: a stream starting or stopping moves its state
const SOURCE_EVENT = "on source #"
# a microphone, real or a filter's virtual one; a sink's monitor is an Audio/Sink
const MIC_CLASS = "Audio/Source"
const MIC_STATE = "RUNNING"

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

# Whether a microphone records, from `pactl -f json list sources`.
export def mic-recording []: list<record> -> bool {
    any {|source|
        ($source.properties?."media.class"? | default "" | str starts-with $MIC_CLASS) and $source.state? == $MIC_STATE
    }
}

# Holds the inhibitor while `wanted` says so, asked again on every line of `events`; with a recheck also on that
# interval while held, so nothing wakes up without a hold.
def guard [who: string, why: string, events: closure, wanted: closure, --recheck: duration] {
    job spawn {
        do $events | each { job send 0 } | ignore
        $ENDED | job send 0
    }
    mut holder: any = null
    while (if $holder == null or $recheck == null { job recv } else { try { job recv --timeout $recheck } catch { $TIMEOUT } }) != $ENDED {
        if (do $wanted) {
            if $holder == null {
                $holder = job spawn { ^systemd-inhibit --what=sleep --mode=block $"--who=($who)" $"--why=($why)" sleep infinity }
            }
        } else if $holder != null {
            job kill $holder
            $holder = null
        }
    }
    # a failure, so Restart=on-failure brings the guard back
    error make {msg: $"($who) guard: its event stream ended"}
}

# video apps inhibit idle themselves; every change re-reads all players, so one paused player cannot release another's hold
def "main media" [] {
    (guard media "media playing" { ^playerctl --all-players --follow status e> /dev/null | lines }
        { ^playerctl --all-players status | complete | get stdout | lines | any { $in == Playing } })
}

# a voice call has no player, and Chromium's suspend blocker asks org.freedesktop.PowerManagement, which nothing here
# provides, so the capture stands for the call; OBS holds its microphone while open. pactl prints nothing on connect,
# so the leading line starts the first check
def "main mic" [] {
    (guard mic "microphone recording" { ^pactl subscribe | lines | where {|line| $line | str contains $SOURCE_EVENT } | prepend "" }
        { ^pactl -f json list sources | complete | get stdout | try { from json } catch { [] } | mic-recording })
}

def "main ssh" [] {
    (guard sshd "ssh session" { ^gdbus monitor --system --dest org.freedesktop.login1 | lines | where $it =~ $SESSION_EVENT }
        { ssh-session-open } --recheck $SSH_RECHECK)
}

def main []: nothing -> nothing {
    print --stderr "usage: sleep-guard media|mic|ssh"
    exit 2
}
