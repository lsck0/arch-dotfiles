#!/usr/bin/env -S nu --no-config-file
# Table cases for desktop-set: whole keys replaced, regex characters in keys and values taken literally.
use module.nu [desktop-set]

def fail [msg: string] { error make {msg: $"module.test: ($msg)"} }

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
        if $got != $c.wants { fail $"($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
}
