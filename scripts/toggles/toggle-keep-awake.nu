#!/usr/bin/env -S nu --no-config-file
use lib.nu [switch-run unit-active]

const UNIT = "toggle-keep-awake.service"
const INHIBIT = [systemd-inhibit --what=sleep:idle --who=toggles "--why=keep-awake toggle enabled" --mode=block sleep infinity]

def main [action: string = "toggle", --json] {
    switch-run {
        label: "Keep awake"
        is-on: {|| unit-active $UNIT --user }
        on: {|| if not (unit-active $UNIT --user) { ^systemd-run --user --quiet --collect $"--unit=($UNIT)" ...$INHIBIT } }
        off: {|| ^systemctl --user stop $UNIT | complete | ignore }
    } $action --json=$json
}
