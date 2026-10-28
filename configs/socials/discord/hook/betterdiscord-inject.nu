#!/usr/bin/env -S nu --no-config-file
# no betterdiscordctl: it hardcodes discord_desktop_core-1, discord ships -2 and up

const REPO = path self | path dirname | path join ../../../.. | path expand
const ASAR_URL = "https://github.com/BetterDiscord/BetterDiscord/releases/download/v1.14.1/betterdiscord.asar"
const ASAR_SHA256 = "8595fffc8a8339f01cdf80b4a34c641cb96cf567732c5227f5c4c6779edff6f6"
const FRESH_SECONDS = 60
const EXIT_WAIT_SECONDS = 10

def main []: nothing -> nothing {
    let config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config)
    let state = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join .local state)
    let asar = $config | path join BetterDiscord data betterdiscord.asar
    let host = $config | path join discord Discord
    let modules_link = $state | path join betterdiscord-modules
    if not ($host | path exists) { return }
    let modules = $host | path expand | path dirname | path join modules
    mkdir ($modules_link | path dirname)
    ^ln -sfn $modules $modules_link
    let core = glob ($modules | path join discord_desktop_core-*) | sort --natural | last 1 | get --optional 0
    let index = $core | default "" | path join discord_desktop_core index.js
    if $core == null or not ($index | path exists) { return }
    let current = ($asar | path exists) and (open --raw $asar | hash sha256) == $ASAR_SHA256
    if $current and (open --raw $index | str contains betterdiscord) { return }
    if not $current { ^nu --no-config-file ($REPO | path join scripts dot.nu) internal fetch file $ASAR_URL $ASAR_SHA256 $asar }
    $"require\(\"($asar)\"\);\nmodule.exports = require\(\"./core.asar\"\);\n" | save --force $index
    relaunch-fresh
}

# Restarts a Discord younger than FRESH_SECONDS: a host update starts it on the bare core, before its modules exist.
def relaunch-fresh []: nothing -> nothing {
    let main = ^pgrep -o -x Discord | complete | get stdout | str trim
    if ($main | is-empty) { return }
    let etime = ^ps -o etimes= -p $main | complete
    if $etime.exit_code != 0 or (($etime.stdout | str trim | into int) >= $FRESH_SECONDS) { return }
    ^pkill -x Discord | complete | ignore
    for _ in 1..$EXIT_WAIT_SECONDS {
        if (^pgrep -x Discord | complete).exit_code != 0 { break }
        sleep 1sec
    }
    # its own scope through uwsm, so it outlives this oneshot's cgroup
    ^uwsm-app -- discord.desktop
}
