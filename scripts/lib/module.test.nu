#!/usr/bin/env -S nu --no-config-file
# Table cases for desktop-set (whole keys replaced, regex characters taken literally) and decls-flatten (any depth).
use module.nu [desktop-set decls-flatten]
use std/assert

def main [] {
    let entry = "[Desktop Entry]\nName=App\nExec=app %U\nX-Key.a=1\n[Desktop Action new]\nExec=app --new\n"
    let cases = [
        [name values wants];
        ["plain value" {Exec: "app --flag %U"} "[Desktop Entry]\nName=App\nExec=app --flag %U\nX-Key.a=1\n[Desktop Action new]\nExec=app --new\n"]
        ["dollar in the value" {Exec: "env A=$HOME app $1"} "[Desktop Entry]\nName=App\nExec=env A=$HOME app $1\nX-Key.a=1\n[Desktop Action new]\nExec=app --new\n"]
        ["regex in the key" {"X-Key.a": 2} "[Desktop Entry]\nName=App\nExec=app %U\nX-Key.a=2\n[Desktop Action new]\nExec=app --new\n"]
        ["absent key" {Icon: "app"} $entry]
    ]
    for c in $cases {
        let got = $entry | desktop-set $c.values
        assert equal $got $c.wants $"($c.name): got ($got | to nuon), wants ($c.wants | to nuon)"
    }
    let a = {kind: file, dest: a, meta: {nested: {kept: true}}}
    let b = {kind: unit, name: b}
    let flat = [
        [name value wants];
        ["null" null []]
        ["single" $a [$a]]
        ["empty" [] []]
        ["three deep" [$a [[$b null] []] [[[$a]]]] [$a $b $a]]
    ]
    for c in $flat {
        let got = $c.value | decls-flatten
        assert equal $got $c.wants $"($c.name): got ($got | to nuon), wants ($c.wants | to nuon)"
    }
}
