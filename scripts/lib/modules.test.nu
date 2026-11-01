#!/usr/bin/env -S nu --no-config-file
# The packages a module's hook can want under every profile and option, which mirror/packages.txt is built from.
use modules.nu [module-packages-every packages-every-context]
use std/assert

const HOOK_MODULE = "use profile.nu [profile-has]
export def packages [cfg: record]: nothing -> record {
    let owner = if (profile-has secrets) { [owner-tool] } else { [plain-tool] }
    let audio = if $cfg.audio == true { [audio-tool] } else { [] }
    {pacman: ($owner ++ $audio ++ [$\"driver-($cfg.driver)\" $\"port-($cfg.port)\"])}
}
"

# The packages every profile and option can want, the same whichever profile the caller runs under.
def packages-every-check [] {
    let repo = mktemp --directory --tmpdir dot-modules-test-XXXXXX
    mkdir ($repo | path join profiles) ($repo | path join platforms) ($repo | path join mod)
    {capabilities: [secrets]} | save ($repo | path join profiles owner.nuon)
    {"x/mod": {port: 2}} | save ($repo | path join platforms box.options.nuon)
    $HOOK_MODULE | save ($repo | path join mod mod.nu)
    let m = {
        id: x/mod, dir: ($repo | path join mod), native: [packages]
        meta: {packages: {pacman: [base-tool], native: [], flatpak: {}, nix: []}}
        options: {driver: {type: "string?", default: null, choices: [open legacy]}, port: {type: int, default: 1}, audio: {type: "bool?", default: null}}
        cfg: {enable: false, driver: legacy, port: 9, audio: null}
    }
    let every = packages-every-context $repo
    let as_owner = with-env {PROFILE_FILE: ($repo | path join profiles owner.nuon)} { module-packages-every $m $every }
    let as_nobody = with-env {PROFILE_FILE: "", XDG_CONFIG_HOME: ($repo | path join none)} { module-packages-every $m $every }
    rm --recursive --force $repo
    let wants = [audio-tool base-tool driver- driver-legacy driver-open owner-tool plain-tool port-1 port-2]
    assert equal ($as_owner | sort) $wants $"packages every: got ($as_owner | sort | to nuon), wants ($wants | to nuon)"
    assert equal $as_owner $as_nobody $"packages every: ($as_owner | to nuon) as the owner, ($as_nobody | to nuon) as nobody"
}

def main [] {
    packages-every-check
}
