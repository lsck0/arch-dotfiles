#!/usr/bin/env -S nu --no-config-file
# steam with the hidden mangohud overlay and obs capture; gamemode stays per game, preloaded into the client it keeps
# gamemode on while steam idles and breaks the webhelper's websocket

const SELF = path self
const GROUP = "games"

# the games group egresses on the real link past proton0 (gaming/vpn-bypass): the vpn slows frontends and risks an
# anticheat ip flag; fail open, without the group steam uses the vpn
def --wrapped main [...args: string]: nothing -> nothing {
    let member = $GROUP in (^id -nG | split row " ")
    if (^id -gn | str trim) != $GROUP and $member and (do { ^sudo -n -g $GROUP true } | complete).exit_code == 0 {
        exec sudo -E -g $GROUP -- $SELF ...$args
    }
    $env.MANGOHUD = "1"
    $env.OBS_VKCAPTURE = "1"
    exec /usr/bin/steam ...$args
}
