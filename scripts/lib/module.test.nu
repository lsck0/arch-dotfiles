#!/usr/bin/env -S nu --no-config-file
# Table cases for desktop-set (whole keys replaced or added in the [Desktop Entry] group only), decls-flatten (any
# depth), unit-restart's argv per layer and flags, and the udev and polkit rule declarations (target, source or
# rendered content, --then), mcp-uvx (the venv built before the registration, which names the venv's entry point), and
# unit-timer's text (key order, Persistent with a calendar, the mains condition) and enabling, and xwayland-scale-for
# (the compositor's option, else its monitors' main scale, else the form factor's).
use module.nu [desktop-set decls-flatten polkit-rules udev-reload udev-rules unit-dir unit-restart unit-timer mcp-uvx xwayland-scale-for]
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
    let install = "\n[Install]\nWantedBy=timers.target\n"
    let ac = "# mains only: 99-x-ac.rules stops it on battery and starts it at the plug-in, where Persistent= catches up\n"
    let timers = [
        [name decls wants];
        ["calendar" (unit-timer x.timer "X weekly" --calendar weekly --delay 1h)
            $"[Unit]\nDescription=X weekly\n\n[Timer]\nOnCalendar=weekly\nPersistent=true\nRandomizedDelaySec=1h\n($install)"]
        ["on mains" (unit-timer x.timer "X" --calendar monthly --ac-power 99-x-ac.rules)
            $"[Unit]\nDescription=X\n($ac)ConditionACPower=true\n\n[Timer]\nOnCalendar=monthly\nPersistent=true\n($install)"]
        ["monotonic" (unit-timer x.timer "X" --boot 2min --startup 1min --every 5min --accuracy 1min)
            $"[Unit]\nDescription=X\n\n[Timer]\nOnBootSec=2min\nOnStartupSec=1min\nOnUnitActiveSec=5min\nAccuracySec=1min\n($install)"]
    ]
    for c in $timers {
        let got = $c.decls | get 0
        assert equal $got.content $c.wants $"unit-timer ($c.name): got ($got.content | to nuon), wants ($c.wants | to nuon)"
        assert equal $got.target (unit-dir | path join x.timer) $"unit-timer ($c.name): target ($got.target)"
    }
    let enabled = with-env {DOT_LAYER: system} { unit-timer x.timer "X" --calendar daily --enable --now }
    assert equal ($enabled | select kind target) [[kind target]; [file /etc/systemd/system/x.timer] [unit x.timer]] $"unit-timer enabled: ($enabled | to nuon)"
    assert equal ($enabled.1 | select state now) {state: enabled, now: true} $"unit-timer enabled: ($enabled.1 | to nuon)"
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
    xwayland-cases
}

def xwayland-cases [] {
    let k4 = {output: DP-1, mode: "3840x2160@144", position: "0x0", scale: 1.0}
    let fhd = {output: DP-2, mode: "1920x1080@60", position: "3840x0", scale: 1.666667}
    let panel = {output: eDP-1, mode: "2880x1800", position: auto, scale: 2.0}
    let hypr = {|o| {deps: {"desktop/hyprland": ({xwayland_scale: null, monitors: null, main_monitor: null} | merge $o)}} }
    let cases = [
        [name cfg form wants];
        ["no compositor read" {deps: {}} desktop 2]
        ["no compositor read, laptop" {} laptop 1]
        ["option set" (do $hypr {xwayland_scale: 3, monitors: [$k4]}) desktop 3]
        ["set monitors beat the form factor" (do $hypr {monitors: [$k4 $fhd]}) desktop 1]
        ["main monitor named" (do $hypr {monitors: [$k4 $fhd], main_monitor: DP-2}) desktop 2]
        ["internal panel is main" (do $hypr {monitors: [$k4 $panel]}) laptop 2]
        ["no monitors" (do $hypr {}) laptop 1]
        ["auto scale" (do $hypr {monitors: [($k4 | update scale auto)]}) desktop 2]
    ]
    for c in $cases {
        let got = with-env {FORM_FACTOR: $c.form} { xwayland-scale-for $c.cfg }
        assert equal $got $c.wants $"xwayland-scale-for ($c.name): got ($got), wants ($c.wants)"
    }
}
