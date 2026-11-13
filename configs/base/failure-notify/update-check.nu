#!/usr/bin/env -S nu --no-config-file

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join scripts lib state.nu) [xdg file-trim]

const EXIT_NO_UPDATES = 2

def main []: nothing -> nothing {
    let state = xdg state update-check
    mkdir $state
    let check = ^checkupdates --nocolor | complete
    if $check.exit_code not-in [0 $EXIT_NO_UPDATES] {
        print --stderr $"update-check: checkupdates failed \(($check.exit_code)\), trying again tomorrow"
        return
    }
    let updates = $check.stdout | lines | where $it != ""
    let audit = if (which arch-audit | is-empty) { {exit_code: 0, stdout: ""} } else {
        ^arch-audit --upgradable --quiet | complete
    }
    if $audit.exit_code != 0 { print --stderr "update-check: arch-audit failed" }
    let advisories = if $audit.exit_code == 0 { $audit.stdout | lines | where $it != "" } else { [] }
    let digest = $updates ++ ["--"] ++ $advisories | str join "\n" | hash sha256
    let last = $state | path join last
    if $digest == (file-trim $last) { return }
    if ($updates | is-not-empty) {
        let security = if ($advisories | is-empty) { "" } else { $"\nsecurity fixes for: ($advisories | str join ' ')" }
        let urgency = if ($advisories | is-empty) { "low" } else { "normal" }
        let body = $"($updates | length) packages, dot sync installs them($security)"
        # no notification daemon yet: unrecorded, so tomorrow's run tries again
        if (^notify-send -a updates -u $urgency "Updates available" $body | complete).exit_code != 0 { return }
    }
    $digest | save --force $last
}
