#!/usr/bin/env -S nu --no-config-file
# gamemode stays per game: preloaded into the client it breaks the webhelper's websocket

const SELF = path self
const GROUP = "games"
const LAUNCH_OPTIONS = path self steam-launch-options.nu

# Steam in the games group, which egresses past proton0 (gaming/vpn-bypass); without the group it stays on the vpn.
def --wrapped main [...args: string]: nothing -> nothing {
    let member = $GROUP in (^id -nG | split row " ")
    if (^id -gn | str trim) != $GROUP and $member and (do { ^sudo -n -g $GROUP true } | complete).exit_code == 0 {
        exec sudo -E -g $GROUP -- $SELF ...$args
    }
    do { ^$nu.current-exe --no-config-file $LAUNCH_OPTIONS } | complete | ignore
    $env.MANGOHUD = "1"
    $env.OBS_VKCAPTURE = "1"
    exec /usr/bin/steam ...$args
}
