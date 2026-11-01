#!/usr/bin/env -S nu --no-config-file
# The banner of a chain stopped before config names the failure, that it is disarmed, the way online and the resume,
# within a tty's lines; the install stage's next step follows the install pass file, not dot's exit code.
use stage.nu [install-banner stage-next STAGE_RESUME]
use std/assert

const ESCAPE = "dot set --machine base/networkmanager.untrusted_policy firewall-only && dot apply --system"
const TTY_LINES = 24
const EXIT_FAILED = 1
const EXIT_PENDING = 3

def banner-cases []: nothing -> nothing {
    let failures = ["pacman: the install pass: download failed 40 times" "" "system layer: install"] ++ (1..20 | each { $"line ($in)" })
    let banner = install-banner 3 $failures
    for want in [$ESCAPE $STAGE_RESUME "failed 3 times" "pacman: the install pass: download failed 40 times" "disarmed" "passphrase"] {
        assert ($banner | str contains $want) $"banner lacks ($want | to nuon):\n($banner)"
    }
    assert not ($banner | str contains "reboot") $"banner still promises a retry on reboot:\n($banner)"
    assert (($banner | lines | length) <= $TTY_LINES) $"banner is ($banner | lines | length) lines, over a tty's ($TTY_LINES)"
    assert not ($banner | lines | any { ($in | str trim) == "" }) "banner shows an empty failure line"
    # the vm test greps the issue file for an indented line starting with the command
    for command in [$ESCAPE $STAGE_RESUME] {
        if not ($banner | lines | any { $in =~ '^\s+dot [a-z]' and ($in | str trim) == $command }) {
            error make {msg: $"banner has no indented line ($command | to nuon):\n($banner)"}
        }
    }
    let bare = install-banner 1 []
    assert (not ($bare | str contains "What failed") and ($bare | str contains $ESCAPE)) $"banner without failures:\n($bare)"
    let kept = install-banner 3 [] --key-kept
    assert (($kept | str contains "unlocks without its passphrase") and not ($kept | str contains "is disarmed")) $"banner with the disk key kept:\n($kept)"
}

def next-cases []: nothing -> nothing {
    let cases = [
        [name stage status passed attempts next tried ok];
        ["pass, dot ok" install 0 true 0 config 0 true]
        ["pass, modules pending" install $EXIT_PENDING true 0 config 0 true]
        ["pass, dot failed after it" install $EXIT_FAILED true 1 config 1 false]
        ["no pass, first attempt" install $EXIT_FAILED false 0 install 1 false]
        ["no pass, dot exited 0" install 0 false 1 install 2 true]
        ["no pass, last attempt" install $EXIT_FAILED false 2 stop 3 false]
        ["no pass, attempts past the limit" install $EXIT_FAILED false 5 stop 6 false]
        ["config ends the chain" config 0 false 2 "" 2 true]
        ["config failed still ends it" config $EXIT_FAILED true 0 "" 0 false]
    ]
    for c in $cases {
        let got = stage-next $c.stage $c.status $c.passed $c.attempts
        let wants = {ok: $c.ok, next: $c.next, attempts: $c.tried}
        assert equal $got $wants $"next ($c.name): got ($got | to nuon), wants ($wants | to nuon)"
    }
}

def main [] {
    banner-cases
    next-cases
}
