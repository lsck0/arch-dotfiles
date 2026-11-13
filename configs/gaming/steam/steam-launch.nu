#!/usr/bin/env -S nu --no-config-file
# gamemode stays per game: preloaded into the client it breaks the webhelper's websocket
# no MANGOHUD=1 on the client either: its shader-precompile helper fossilize_replay loads the layer and aborts at exit

use ../../../scripts/lib/state.nu [xdg]

const SELF = path self
const GROUP = "vpn-bypass"
const GAMES_RUN = "/usr/local/bin/games-run"
# The session environment for the child under games-run, which pkexec clears. It stays in the owner-only runtime dir
# rather than on pkexec's command line, which lands in the journal and the prompt. The child removes it on start, so a
# stash still there after pkexec returns means the child never ran.
const STASH_NAME = "steam-launch.env"
# set by nushell itself, refused by load-env
const ENV_AUTOMATIC = [PWD FILE_PWD CURRENT_FILE]
const LAUNCH_OPTIONS = path self steam-launch-options.nu
# gaming/vpn-bypass's tunnel (games-route.nu VPN_IFACE): without it there is nothing to bypass, so no key prompt
const VPN_IFACE = "proton0"

def --env stash-load [stash: path]: nothing -> nothing {
    let text = open --raw $stash
    rm --force $stash
    $text | split row (char nul) | where $it != "" | parse --regex '(?s)^(?<k>[^=]+)=(?<v>.*)$'
    | where k not-in $ENV_AUTOMATIC | transpose --header-row --as-record | load-env
}

# Steam in the vpn-bypass group, which egresses past proton0 (gaming/vpn-bypass), after one key touch through games-run;
# with no vpn up (at home, say) it starts as is, unasked; with the prompt dismissed it stays on the vpn.
def --wrapped main [...args: string]: nothing -> nothing {
    let stash = xdg runtime $STASH_NAME
    if (^id -gn | str trim) == $GROUP {
        if ($stash | path exists) { stash-load $stash }
    } else if ($"/sys/class/net/($VPN_IFACE)" | path exists) and ($GAMES_RUN | path exists) and (which pkexec | is-not-empty) {
        ^env -0 | save --force $stash
        let code = try { ^pkexec --keep-cwd $GAMES_RUN $SELF ...$args; 0 } catch {|e| $e.exit_code? | default 1 }
        if not ($stash | path exists) { exit $code }
        rm --force $stash
    }
    do { ^$nu.current-exe --no-config-file $LAUNCH_OPTIONS } | complete | ignore
    $env.OBS_VKCAPTURE = "1"
    exec /usr/bin/steam ...$args
}
