#!/usr/bin/env -S nu --no-config-file
# The banner of a chain stopped before config names the failure, that it is disarmed, the way online and the resume,
# within a tty's lines; the install stage's next step follows the install pass file, not dot's exit code.
use stage.nu [install-banner config-banner stage-next stage-sudoers STAGE_RESUME]
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
    let config = config-banner (["base/x link/step y: z" ""] ++ (1..20 | each { $"m/($in) link/eval: e" }))
    for want in ["config stage failed" "base/x link/step y: z" "dot apply" "FAILURES.config"] {
        assert ($config | str contains $want) $"config banner lacks ($want | to nuon):\n($config)"
    }
    assert (($config | lines | length) <= $TTY_LINES) $"config banner is ($config | lines | length) lines"
    assert not ($config | lines | any { ($in | str trim) == "" }) "config banner shows an empty failure line"
    assert not (config-banner [] | str contains "What failed") "config banner without failures lists some"
}

def next-cases []: nothing -> nothing {
    let cases = [
        [name stage status passed attempts next ok];
        ["pass, dot ok" install 0 true 1 config true]
        ["pass, modules pending" install $EXIT_PENDING true 1 config true]
        ["pass, dot failed after it" install $EXIT_FAILED true 2 config false]
        ["no pass, first attempt" install $EXIT_FAILED false 1 install false]
        ["no pass, dot exited 0" install 0 false 2 install true]
        ["no pass, last attempt" install $EXIT_FAILED false 3 stop false]
        ["no pass, attempts past the limit" install $EXIT_FAILED false 6 stop false]
        ["config ends the chain" config 0 false 2 "" true]
        ["config failed still ends it" config $EXIT_FAILED true 0 "" false]
    ]
    for c in $cases {
        let got = stage-next $c.stage $c.status $c.passed $c.attempts
        let wants = {ok: $c.ok, next: $c.next}
        assert equal $got $wants $"next ($c.name): got ($got | to nuon), wants ($wants | to nuon)"
    }
}

# visudo is the one authority on the syntax: a broken drop-in would silently strand the install chain without sudo.
def sudoers-cases []: nothing -> nothing {
    if (which visudo | is-empty) { return }
    for user in [luca my-user a_b] {
        let file = mktemp --tmpdir
        stage-sudoers $user | save --force $file
        let check = ^visudo -cf $file | complete
        rm --force $file
        assert equal $check.exit_code 0 $"stage-sudoers ($user): visudo rejects it: ($check.stdout)($check.stderr)"
    }
}

def main [] {
    banner-cases
    next-cases
    sudoers-cases
}
