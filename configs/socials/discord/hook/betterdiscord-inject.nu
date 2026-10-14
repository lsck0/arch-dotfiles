#!/usr/bin/env -S nu --no-config-file
# runs on every module change, so the injected check comes first; no betterdiscordctl: it hardcodes
# discord_desktop_core-1, discord ships -2 and up

const REPO = path self | path dirname | path join ../../../.. | path expand
# runs inside discord with the account token, so a pinned release; bump both together
const ASAR_URL = "https://github.com/BetterDiscord/BetterDiscord/releases/download/v1.14.1/betterdiscord.asar"
const ASAR_SHA256 = "8595fffc8a8339f01cdf80b4a34c641cb96cf567732c5227f5c4c6779edff6f6"

def main []: nothing -> nothing {
    let asar = $nu.home-dir | path join .config BetterDiscord data betterdiscord.asar
    let host = $nu.home-dir | path join .config discord Discord
    # the path unit watches this: it follows the host the updater switches to, whose modules dir gets each core update
    let modules_link = $nu.home-dir | path join .local state betterdiscord-modules
    if not ($host | path exists) { return }
    let modules = $host | path expand | path dirname | path join modules
    mkdir ($modules_link | path dirname)
    ^ln -sfn $modules $modules_link
    let core = glob ($modules | path join discord_desktop_core-*) | sort --natural | last 1 | get --optional 0
    let index = $core | default "" | path join discord_desktop_core index.js
    if $core == null or not ($index | path exists) { return }
    let current = ($asar | path exists) and (open --raw $asar | hash sha256) == $ASAR_SHA256
    if $current and (open --raw $index | str contains betterdiscord) { return }
    if not $current { ^nu --no-config-file ($REPO | path join scripts dot.nu) fetch file $ASAR_URL $ASAR_SHA256 $asar }
    # the same two lines the official installer writes
    $"require\(\"($asar)\"\);\nmodule.exports = require\(\"./core.asar\"\);\n" | save --force $index
}
