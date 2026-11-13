#!/usr/bin/env -S nu --no-config-file
# Package resolution: no declared names resolve to no packages, never to everything pacman -Q lists, and a convergence
# with nothing resolved offers nothing for removal. A corrupt ledger reads what it still holds: a cut-off last line and
# bytes that are no UTF-8 are skipped, and the next ledger-set writes it whole. ledger-units declares a unit spelled in a
# module dir or scripts/ and one only a module's record holds enabled, root modules included, against a stub systemctl.
use ledger.nu [packages-resolve packages-convergence ledger-get ledger-set ledger-file ledger-units]
use std/assert

def corrupt-cases []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-ledger-test.XXXXXX
    with-env {XDG_STATE_HOME: $dir, DOT_LAYER: user} {
        let file = ledger-file
        mkdir ($file | path dirname)
        let cases = [
            [name bytes wants];
            ["whole" ("migration a\nmigration b\npkg x\n" | into binary) [a b]]
            ["last line cut off" ("migration a\nmigration b\nmigration c-cut" | into binary) [a b]]
            ["no utf-8" (0x[00 ff 7b 0a] | bytes add --end ("migration a\n" | into binary)) [a]]
            ["empty" 0x[] []]
        ]
        for c in $cases {
            $c.bytes | save --force --raw $file
            let got = ledger-get migration
            assert equal $got $c.wants $"ledger ($c.name): got ($got | to nuon)"
        }
        "migration a\nmigration b-cut" | save --force $file
        ledger-set pkg [x]
        assert equal (open --raw $file) "migration a\npkg x\n" "ledger: a set after a cut-off line wrote it back"
        "migration a\nmigration b-cut" | save --force $file
        let run = $dir | path join run.jsonl
        with-env {DOT_RUN_FILE: $run, DOT_RUN_ID: test} { ledger-get migration; ledger-get pkg; ledger-get migration } | ignore
        let warned = open --raw $run | lines | where ($it | str contains "cut off") | length
        assert equal $warned 1 $"ledger: a cut-off line warned ($warned) times in one run"
        rm $file
        assert equal (ledger-get migration) [] "ledger: no file, nothing recorded"
    }
    rm --recursive --force $dir
}

def units-cases []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-ledger-test.XXXXXX
    let repo = $dir | path join repo
    let module = $repo | path join configs g m
    mkdir $module ($repo | path join scripts) ($repo | path join skills) ($dir | path join bin)
    "unit-enable foo.service" | save ($module | path join mod.nu)
    "systemctl start bar.timer" | save ($repo | path join scripts run.nu)
    let records = $dir | path join state dotfiles modules
    mkdir ($records | path join skills)
    {outputs: [{kind: unit, target: hook-x.service, state: enabled} {kind: unit, target: off.service, state: disabled}]} | to nuon
    | save ($records | path join skills link.nuon)
    # is-enabled answers enabled for each unit; nothing is enabled outside dot
    "#!/bin/sh
[ "$2" = is-enabled ] || exit 0
shift 2
for u in "$@"; do echo enabled; done
" | save ($dir | path join bin systemctl)
    ^chmod +x ($dir | path join bin systemctl)
    let modules = [[id dir]; [g/m $module] [skills ($repo | path join skills)]]
    with-env {XDG_STATE_HOME: ($dir | path join state), DOT_LAYER: user, DOTFILES_UNATTENDED: 1, PATH: ($env.PATH | prepend ($dir | path join bin))} {
        let got = ledger-units $repo $modules user
        assert equal $got.owned [bar.timer foo.service hook-x.service] $"ledger-units: owned ($got.owned | to nuon)"
        assert equal $got.dropped [] $"ledger-units: dropped ($got.dropped | to nuon)"
        assert equal (ledger-get unit) ["user bar.timer" "user foo.service" "user hook-x.service"] "ledger-units: ledger written"
    }
    rm --recursive --force $dir
}

def main []: nothing -> nothing {
    corrupt-cases
    units-cases
    assert equal (packages-resolve []) [] "no declared packages resolved to installed ones"
    if (which pacman | is-empty) { return }
    let none = packages-convergence [] []
    assert equal $none.remove [] $"nothing declared offers ($none.remove | length) packages for removal"
    let unknown = packages-convergence [dot-test-no-such-package] []
    assert equal $unknown.remove [] $"nothing resolved offers ($unknown.remove | length) packages for removal"
}
