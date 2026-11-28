#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run unit-active failure-raise]

const UNIT = "toggle-keep-awake.service"
const INHIBIT = [systemd-inhibit --what=sleep:idle --who=toggles "--why=keep-awake toggle enabled" --mode=block sleep infinity]

# Keep awake: get [--json] prints the state, on, off or toggle switches it, a bare call toggles.
def main [action: string = "toggle", --json] {
    switch-run {
        label: "Keep awake"
        is-on: {|| unit-active $UNIT --user }
        on: {|| ^systemd-run --user --quiet --collect $"--unit=($UNIT)" ...$INHIBIT }
        off: {|| ^systemctl --user stop $UNIT | complete | failure-raise systemctl }
    } $action --json=$json
}
