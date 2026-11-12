#!/usr/bin/env -S nu --no-config-file
# no betterdiscordctl: it assumes one discord_desktop_core suffix, which differs between hosts

use ../../../../scripts/lib/state.nu [xdg]

const REPO = path self ../../../..
const ASAR_URL = "https://github.com/BetterDiscord/BetterDiscord/releases/download/v1.14.5/betterdiscord.asar"
const ASAR_SHA256 = "2576f2b1dcb3bf5fdc79a5ef137a077543aa9aa0ffcd8337e8c27b8260fc49f3"
const FRESH_SECONDS = 60
const EXIT_WAIT_SECONDS = 10

def main []: nothing -> nothing {
    let asar = xdg config BetterDiscord data betterdiscord.asar
    let host = xdg config discord Discord
    let modules_link = xdg state betterdiscord-modules
    if not ($host | path exists) { return }
    let modules = $host | path expand | path dirname | path join modules
    mkdir ($modules_link | path dirname)
    ^ln -sfn $modules $modules_link
    let core = glob ($modules | path join discord_desktop_core-*) | sort --natural | last 1 | get --optional 0
    let index = $core | default "" | path join discord_desktop_core index.js
    if $core == null or not ($index | path exists) { return }
    let current = ($asar | path exists) and (open --raw $asar | hash sha256) == $ASAR_SHA256
    let require = $"require\(\"($asar)\"\);"
    let injected = open --raw $index | str contains $require
    if $current and $injected { return }
    if not $current { ^nu --no-config-file ($REPO | path join scripts dot.nu) internal fetch file $ASAR_URL $ASAR_SHA256 $asar }
    $"($require)\nmodule.exports = require\(\"./core.asar\"\);\n" | save --force $index
    # a running discord already loaded betterdiscord through this index: a new asar takes effect on its next start
    if not $injected { relaunch-fresh }
}

# Restarts a Discord younger than FRESH_SECONDS: a host update starts it on the bare core, before its modules exist.
def relaunch-fresh []: nothing -> nothing {
    let main = ^pgrep -o -x Discord | complete | get stdout | str trim
    if ($main | is-empty) { return }
    let etime = ^ps -o etimes= -p $main | complete
    if $etime.exit_code != 0 or (($etime.stdout | str trim | into int) >= $FRESH_SECONDS) { return }
    # without uwsm nothing could start it again
    if (which uwsm-app | is-empty) { return }
    ^pkill -x Discord | complete | ignore
    for _ in 1..$EXIT_WAIT_SECONDS {
        if (^pgrep -x Discord | complete).exit_code != 0 { break }
        sleep 1sec
    }
    # a transient service: uwsm-app returns at once, so this oneshot does not hold discord as its child
    ^uwsm-app -t service -- discord.desktop
}
