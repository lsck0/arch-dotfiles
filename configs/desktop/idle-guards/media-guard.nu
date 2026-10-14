#!/usr/bin/env -S nu --no-config-file
# holds a sleep inhibitor while any player plays, so the machine never suspends under it; dim and lock still happen,
# video apps inhibit idle themselves

const ENDED = "ended"

def playing []: nothing -> bool {
    ^playerctl --all-players status | complete | get stdout | lines | any { $in == Playing }
}

def main [] {
    # --follow only wakes us on a change; the aggregate is re-read so one paused player cannot release another's hold
    job spawn {
        ^playerctl --all-players --follow status e>| ignore | lines | each { job send 0 } | ignore
        $ENDED | job send 0
    }
    mut holder: any = null
    while (job recv) != $ENDED {
        if (playing) {
            if $holder == null {
                $holder = job spawn { ^systemd-inhibit --what=sleep --mode=block --who=media --why="media playing" sleep infinity }
            }
        } else if $holder != null {
            job kill $holder
            $holder = null
        }
    }
    # the monitor ending is a failure, so Restart=on-failure brings the guard back
    error make {msg: "playerctl --follow ended"}
}
