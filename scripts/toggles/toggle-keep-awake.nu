#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run]

const UNIT = "toggle-keep-awake.service"
const INHIBIT = [systemd-inhibit --what=sleep:idle --who=toggles "--why=keep-awake toggle enabled" --mode=block sleep infinity]

def inhibiting []: nothing -> bool {
    (^systemctl --user is-active --quiet $UNIT | complete).exit_code == 0
}

def main [action: string = "toggle", --json] {
    switch-run {
        label: "Keep awake"
        is-on: {|| inhibiting }
        on: {|| if not (inhibiting) { ^systemd-run --user --quiet --collect $"--unit=($UNIT)" ...$INHIBIT } }
        off: {|| ^systemctl --user stop $UNIT | complete | ignore }
    } $action --json=$json
}
