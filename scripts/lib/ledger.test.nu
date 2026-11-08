#!/usr/bin/env -S nu --no-config-file
# Package resolution: no declared names resolve to no packages, never to everything pacman -Q lists, and a convergence
# with nothing resolved offers nothing for removal. A corrupt ledger reads what it still holds: a cut-off last line and
# bytes that are no UTF-8 are skipped, and the next ledger-set writes it whole.
use ledger.nu [packages-resolve packages-convergence ledger-get ledger-set ledger-file]
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

def main []: nothing -> nothing {
    corrupt-cases
    assert equal (packages-resolve []) [] "no declared packages resolved to installed ones"
    if (which pacman | is-empty) { return }
    let none = packages-convergence [] []
    assert equal $none.remove [] $"nothing declared offers ($none.remove | length) packages for removal"
    let unknown = packages-convergence [dot-test-no-such-package] []
    assert equal $unknown.remove [] $"nothing resolved offers ($unknown.remove | length) packages for removal"
}
