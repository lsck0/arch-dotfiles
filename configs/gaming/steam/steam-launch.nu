#!/usr/bin/env -S nu --no-config-file
# steam with the mangohud overlay (hidden until toggled) and obs capture ready for every game; gamemode stays per game
# (launch option `gamemoderun %command%`): preloaded into the client it registers steam and steamwebhelper, keeps
# gamemode on while steam idles and breaks the webhelper's websocket

const SELF = path self
const GROUP = "games"

# steam and every game it starts run as the games group, so their sockets egress on the real link even while proton0
# is up (configs/gaming/vpn-bypass): the vpn only slows game frontends and risks an anticheat ip flag, and a game
# reveals the player anyway. fail open: without the group or its sudoers, steam uses the vpn like everything else
def --wrapped main [...args: string]: nothing -> nothing {
    let member = $GROUP in (^id -nG | split row " ")
    if (^id -gn | str trim) != $GROUP and $member and (do { ^sudo -n -g $GROUP true } | complete).exit_code == 0 {
        exec sudo -E -g $GROUP -- $SELF ...$args
    }
    $env.MANGOHUD = "1"
    $env.OBS_VKCAPTURE = "1"
    exec /usr/bin/steam ...$args
}
