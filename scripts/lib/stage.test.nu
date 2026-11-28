#!/usr/bin/env -S nu --no-config-file
# The banner of a chain stopped before config names the failure, that it is disarmed, the way online (a root edit where
# the platform's options are root's, which dot set refuses) and the resume, within a tty's lines; the install stage's
# next step follows the install pass file, not dot's exit code. A chain that ends with modules waiting on the network
# says so, and why, where DNS-over-TLS was blocked.
use stage.nu [install-banner config-banner pending-banner stage-argv stage-next stage-sudoers STAGE_RESUME]
use online.nu [OFFLINE_PENDING DNS_TLS_PENDING DNS_TLS_BLOCKED]
use std/assert

const ESCAPE = "dot set --machine base/networkmanager.untrusted_policy firewall-only && dot apply --system"
const OPTIONS_ROOT = "/etc/dotfiles/platform.options.nuon"
const ESCAPE_ROOT = $"sudoedit ($OPTIONS_ROOT) && dot apply --system"
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
    # dot set refuses root's options file, a custom or server platform's
    let rooted = install-banner 1 [] --options-file $OPTIONS_ROOT
    let edit = $rooted | lines | any { ($in | str trim) == $ESCAPE_ROOT }
    assert ($edit and not ($rooted | str contains "dot set")) $"banner of a platform whose options are root's:\n($rooted)"
    assert ($rooted | str contains "untrusted_policy: firewall-only") $"banner of root's options names no policy:\n($rooted)"
    let named = install-banner 1 [] --options-file /home/u/arch-dotfiles/platforms/pc.options.nuon
    assert ($named | str contains $ESCAPE) $"banner of a repo platform lacks dot set:\n($named)"
    let kept = install-banner 3 [] --key-kept
    assert (($kept | str contains "unlocks without its passphrase") and not ($kept | str contains "is disarmed")) $"banner with the disk key kept:\n($kept)"
    let config = config-banner (["base/x link/step y: z" ""] ++ (1..20 | each { $"m/($in) link/eval: e" })) 1
    for want in ["config stage failed" "base/x link/step y: z" "dot apply" "FAILURES.config"] {
        assert ($config | str contains $want) $"config banner lacks ($want | to nuon):\n($config)"
    }
    assert (($config | lines | length) <= $TTY_LINES) $"config banner is ($config | lines | length) lines"
    assert not ($config | lines | any { ($in | str trim) == "" }) "config banner shows an empty failure line"
    let bare = config-banner [] 125
    assert not ($bare | str contains "What failed") "config banner without failures lists some"
    assert ($bare | str contains "exited 125") $"config banner without failures hides the exit code:\n($bare)"
}

# The VM's chain: core/cli's download offline, five modules behind it; strict dot blocked or plainly offline.
def pending-cases []: nothing -> nothing {
    let waiting = [core/tmux core/wallust core/git core/herdr core/btop core/yazi]
    for c in [[pending dns_tls]; [$OFFLINE_PENDING false] [$DNS_TLS_PENDING true]] {
        let banner = pending-banner {offline: [$"core/cli: ($c.pending)"], waiting: $waiting}
        for want in ["wait on the network" $"core/cli: ($c.pending)" "core/tmux" "core/yazi" "dot apply" "dot status"] {
            assert ($banner | str contains $want) $"pending banner lacks ($want | to nuon):\n($banner)"
        }
        assert equal ($banner | str contains $ESCAPE) (not $c.dns_tls) $"pending banner, dns_tls ($c.dns_tls), firewall escape:\n($banner)"
        assert equal ($banner | str contains "allow tcp 853 out") $c.dns_tls $"pending banner, dns_tls ($c.dns_tls), 853 escape:\n($banner)"
        assert (($banner | lines | length) <= $TTY_LINES) $"pending banner is ($banner | lines | length) lines"
        assert not ($banner | lines | any { ($in | str trim) == "" }) "pending banner shows an empty line"
    }
    let many = pending-banner {offline: (1..20 | each { $"m/($in): ($OFFLINE_PENDING)" }), waiting: (1..30 | each { $"w/($in)" })}
    assert (($many | lines | length) <= $TTY_LINES) $"pending banner of many is ($many | lines | length) lines"
    assert ($many | str contains "and 15 more") $"pending banner of many hides its count:\n($many)"
    let rooted = pending-banner {offline: [$"core/cli: ($OFFLINE_PENDING)"], waiting: []} --options-file $OPTIONS_ROOT
    assert (($rooted | str contains $ESCAPE_ROOT) and not ($rooted | str contains "Waiting on")) $"pending banner of root's options:\n($rooted)"
    let blocked = install-banner 3 [] --dns-tls
    assert (($blocked | str contains $DNS_TLS_BLOCKED) and not ($blocked | str contains $ESCAPE)) $"install banner with dot blocked:\n($blocked)"
    assert ($blocked | lines | any { ($in | str trim) == $STAGE_RESUME }) $"install banner with dot blocked lost the resume:\n($blocked)"
}

# the stage commands themselves run: GNU timeout refused nushell's `1min` once, so config never ran (VM run 2)
def argv-cases []: nothing -> nothing {
    for stage in [install config] {
        let argv = stage-argv $stage ["true"]
        let r = do { ^$argv.0 ...($argv | skip 1) } | complete
        assert equal $r.exit_code 0 $"($stage) stage command ($argv | to nuon) failed: ($r.stderr)"
    }
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
    pending-cases
    next-cases
    sudoers-cases
    argv-cases
}
