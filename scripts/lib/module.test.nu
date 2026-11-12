#!/usr/bin/env -S nu --no-config-file
# Table cases for desktop-set (whole keys replaced or added in the [Desktop Entry] group only) and decls-flatten (any
# depth).
use module.nu [desktop-set decls-flatten]
use std/assert

def main [] {
    let action = "\n[Desktop Action new]\nExec=app --new\nIcon=new\n"
    let entry = $"[Desktop Entry]\nName=App\nExec=app %U\nX-Key.a=1\nName[de]=Anw\n($action)"
    let cases = [
        [name values wants];
        ["plain value" {Exec: "app --flag %U"} ($entry | str replace "Exec=app %U" "Exec=app --flag %U")]
        ["dollar in the value" {Exec: "env A=$HOME app $1"} ($entry | str replace "Exec=app %U" "Exec=env A=$HOME app $1")]
        ["regex in the key" {"X-Key.a": 2} ($entry | str replace "X-Key.a=1" "X-Key.a=2")]
        ["localized key kept" {Name: "Tool"} ($entry | str replace "Name=App" "Name=Tool")]
        ["absent key, present in an action" {Icon: "app"} ($entry | str replace "]\nName=App" "]\nIcon=app\nName=App")]
        ["absent key with a dollar" {NoDisplay: true, X-Run: "a $1"} ($entry | str replace "]\nName" "]\nNoDisplay=true\nX-Run=a $1\nName")]
        ["present and absent" {NoDisplay: false, Name: "Tool"} ($entry | str replace "]\nName=App" "]\nNoDisplay=false\nName=Tool")]
        ["no values" {} $entry]
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
