#!/usr/bin/env -S nu --no-config-file
# Table cases for desktop-set (whole keys replaced or added in the [Desktop Entry] group only), decls-flatten (any
# depth), unit-restart's argv per layer and flags, and the udev and polkit rule declarations (target, source or
# rendered content, --then).
use module.nu [desktop-set decls-flatten polkit-rules udev-reload udev-rules unit-restart]
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
    let guarded = {|layer verb| [sh -c $"! systemctl --($layer) cat x.service >/dev/null 2>&1 || systemctl --($layer) ($verb) x.service"] }
    let restarts = [
        [name layer got wants];
        ["user restart" user {|| unit-restart x.service } (do $guarded user restart)]
        ["system restart" system {|| unit-restart x.service } (do $guarded system restart)]
        ["reload" system {|| unit-restart x.service --reload } (do $guarded system reload-or-restart)]
        ["if running" user {|| unit-restart x.service --if-running } (do $guarded user try-restart)]
        ["reload if running" system {|| unit-restart x.service --reload --if-running } (do $guarded system try-reload-or-restart)]
    ]
    for c in $restarts {
        let got = with-env {DOT_LAYER: $c.layer} { do $c.got }
        assert equal $got $c.wants $"($c.name): got ($got | to nuon), wants ($c.wants | to nuon)"
    }
    let reload = [udevadm control --reload]
    let none = if false { "" }
    let reloads = [
        [name got wants];
        ["bare" (udev-reload) $reload]
        ["trigger" (udev-reload --action=add --subsystem-match=net) [sh -c "udevadm control --reload && udevadm trigger --action=add --subsystem-match=net"]]
        ["trigger and" (udev-reload --subsystem-match=input --and "systemctl restart x.service") [sh -c "udevadm control --reload && udevadm trigger --subsystem-match=input && systemctl restart x.service"]]
        ["null and" (udev-reload --subsystem-match=input --and $none) [sh -c "udevadm control --reload && udevadm trigger --subsystem-match=input"]]
        ["and alone" (udev-reload --and "true") [sh -c "udevadm control --reload && true"]]
    ]
    for c in $reloads {
        assert equal $c.got $c.wants $"($c.name): got ($c.got | to nuon), wants ($c.wants | to nuon)"
    }
    let dir = mktemp --directory
    cd $dir
    "a @K@ b" | save x.rules
    let src = $dir | path join x.rules
    let udev = "/etc/udev/rules.d/x.rules"
    let polkit = "/etc/polkit-1/rules.d"
    let rules = [
        [name decl wants];
        ["udev reload" (udev-rules x.rules) {target: $udev, source: $src, then: $reload}]
        ["udev trigger" (udev-rules x.rules --subsystem-match=block) {target: $udev, source: $src, then: (udev-reload --subsystem-match=block)}]
        ["udev own then" (udev-rules x.rules --then [a b]) {target: $udev, source: $src, then: [a b]}]
        ["polkit copy" (polkit-rules x.rules) {target: $"($polkit)/x.rules", source: $src, content: null}]
        ["polkit renamed" (polkit-rules x.rules --name 50-y.rules) {target: $"($polkit)/50-y.rules", source: $src}]
        ["polkit rendered" (polkit-rules x.rules --values {K: 1}) {target: $"($polkit)/x.rules", source: null, content: "a 1 b"}]
    ]
    for c in $rules {
        let got = $c.decl | select ...($c.wants | columns)
        assert equal $got $c.wants $"($c.name): got ($got | to nuon), wants ($c.wants | to nuon)"
    }
    cd ($dir | path dirname)
    rm --recursive $dir
}
