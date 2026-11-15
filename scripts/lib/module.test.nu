#!/usr/bin/env -S nu --no-config-file
# Table cases for desktop-set (whole keys replaced or added in the [Desktop Entry] group only), decls-flatten (any
# depth), unit-restart's argv per layer and flags, and the udev and polkit rule declarations (target, source or
# rendered content, --then), and mcp-uvx (the venv built before the registration, which names the venv's entry point).
use module.nu [desktop-set decls-flatten polkit-rules udev-reload udev-rules unit-restart mcp-uvx]
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
    if (which uv | is-not-empty) {
        let venv = $dir | path join data mcp tool
        let decls = with-env {XDG_DATA_HOME: ($dir | path join data)} { mcp-uvx tool "tool-mcp==1.2" "2026-01-01" [tool-mcp serve] tool_mcp --python "3.12" --env-vars {A: b} }
        let build = $decls | first
        assert equal ($build | select kind creates key network undo) {kind: exec, creates: ($venv | path join bin python), key: "tool-mcp==1.2@2026-01-01-py3.12", network: true, undo: [rm -rf $venv]} $"mcp-uvx build: ($build | to nuon)"
        assert equal ($build.argv | skip 3) [$venv "2026-01-01" "tool-mcp==1.2" tool_mcp tool-mcp --python "3.12"] $"mcp-uvx build argv: ($build.argv | to nuon)"
        # a build that fails leaves the live venv, and so the registered command, as it was
        mkdir ($venv | path join bin)
        "live\n" | save ($venv | path join bin tool-mcp)
        let failed = with-env {UV_OFFLINE: 1, UV_CACHE_DIR: ($dir | path join uv-cache)} { ^$build.argv.0 ...($build.argv | skip 1 | update 4 "mcp-uvx-test-absent==0") | complete }
        assert ($failed.exit_code != 0) "mcp-uvx build: installing a package no index has went through"
        assert equal (open --raw ($venv | path join bin tool-mcp)) "live\n" "mcp-uvx build: a failed build replaced the live venv"
        # the done check follows bin/python, so a venv whose interpreter is gone counts as not built
        ^ln -s ($dir | path join gone-python) ($venv | path join bin python)
        assert not ($build.creates | path exists) "mcp-uvx build: a venv with a dead python counts as built"
        let claude = $decls | skip 1 | first | get edits.0.value
        assert equal $claude {type: stdio, command: ($venv | path join bin tool-mcp), args: [serve], env: {A: b}} $"mcp-uvx registration: ($claude | to nuon)"
    }
    cd ($dir | path dirname)
    rm --recursive $dir
}
