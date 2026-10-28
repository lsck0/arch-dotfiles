#!/usr/bin/env -S nu --no-config-file
# a sleep inhibitor while any player plays; dim and lock still happen, video apps inhibit idle themselves

const ENDED = "ended"

def playing []: nothing -> bool {
    ^playerctl --all-players status | complete | get stdout | lines | any { $in == Playing }
}

def main [] {
    job spawn {
        ^playerctl --all-players --follow status e> /dev/null | lines | each { job send 0 } | ignore
        $ENDED | job send 0
    }
    mut holder: any = null
    while (job recv) != $ENDED {
        # every change re-reads all players, so one paused player cannot release another's hold
        if (playing) {
            if $holder == null {
                $holder = job spawn { ^systemd-inhibit --what=sleep --mode=block --who=media --why="media playing" sleep infinity }
            }
        } else if $holder != null {
            job kill $holder
            $holder = null
        }
    }
    # a failure, so Restart=on-failure brings the guard back
    error make {msg: "playerctl --follow ended"}
}
