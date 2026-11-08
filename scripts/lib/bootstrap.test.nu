#!/usr/bin/env -S nu --no-config-file
# bootstrap-profile-resolve and bootstrap-platform-resolve against a throwaway repo: custom resolves to no file, a
# named pick reads its capabilities or its platform's groups, and an unknown pick or server-on-wsl dies. The groups
# answer unattended, the install chain's ESP marker, and the live pacman.conf's [lsck0] with the lab up and down.
use bootstrap.nu [bootstrap-profile-resolve bootstrap-platform-resolve answer-groups stage-marker-state pacman-conf-lsck0]
use stage.nu [STAGE_ESP_RUNNING STAGE_ESP_STOPPED]
use platform.nu [platform-groups-all]
use std/assert

const QUESTIONS = path self bootstrap/questions.nuon
const REPO = path self ../..
const PACMAN_LSCK0 = "[options]\nArchitecture = auto\n\n[lsck0]\nServer = https://mirror.example/lsck0\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n"
const PACMAN_PLAIN = "[options]\nArchitecture = auto\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n"

const PROFILE_E = {invalid: "unknown profile '{value}'", options: [{value: "custom", label: "nothing personal"}]}
const PLATFORM_E = {invalid: "unknown machine '{value}'", invalid_wsl: "server is not for WSL", hidden: [vm server]}

def fixture []: nothing -> path {
    let repo = mktemp --directory --tmpdir bootstrap-test.XXXXXX
    mkdir ($repo | path join profiles) ($repo | path join platforms)
    {capabilities: [secrets]} | to nuon | save ($repo | path join profiles luca.nuon)
    {hostname: vm, groups: [base core]} | to nuon | save ($repo | path join platforms vm.nuon)
    for g in [base core desktop gaming programming secrets] { mkdir ($repo | path join configs $g) }
    $repo
}

def dies [closure: closure]: nothing -> bool {
    try { do $closure; false } catch { true }
}

def profile-cases [repo: path]: nothing -> nothing {
    assert equal (bootstrap-profile-resolve $repo $PROFILE_E custom) {profile: custom, profile_file: "", capabilities: []} "profile: custom"
    let luca = bootstrap-profile-resolve $repo $PROFILE_E luca
    assert equal $luca.profile luca "profile: luca name"
    assert equal $luca.profile_file ($repo | path join profiles luca.nuon) "profile: luca file"
    assert equal $luca.capabilities [secrets] "profile: luca capabilities"
    assert (dies {|| bootstrap-profile-resolve $repo $PROFILE_E nonexistent }) "profile: an unknown name must die"
}

def platform-cases [repo: path]: nothing -> nothing {
    with-env {BOOTSTRAP_SERVER: ""} {
        let custom = bootstrap-platform-resolve $repo $PLATFORM_E custom false
        assert equal $custom {platform: custom, generic: true, server: false} "platform: custom"
        let vm = bootstrap-platform-resolve $repo $PLATFORM_E vm false
        assert equal $vm {platform: vm, generic: false, server: false} "platform: a named platform"
        assert (dies {|| bootstrap-platform-resolve $repo $PLATFORM_E nonexistent false }) "platform: an unknown name must die"
    }
    with-env {BOOTSTRAP_SERVER: "1"} {
        let server = bootstrap-platform-resolve $repo $PLATFORM_E custom false
        assert equal $server {platform: server, generic: true, server: true} "platform: custom plus BOOTSTRAP_SERVER=1 becomes server"
        assert (dies {|| bootstrap-platform-resolve $repo $PLATFORM_E custom true }) "platform: server on wsl must die"
    }
    with-env {BOOTSTRAP_SERVER: "2"} {
        assert (dies {|| bootstrap-platform-resolve $repo $PLATFORM_E custom false }) "platform: a bad BOOTSTRAP_SERVER must die"
    }
}

# Unattended, the groups are the question's preset (fonts, absent from this repo, dropped) unless BOOTSTRAP_GROUPS
# names them; a server keeps its platform's, and an unknown group dies.
def groups-cases [repo: path]: nothing -> nothing {
    let e = open $QUESTIONS | get questions | where $it.id? == groups | first
    let c = {repo: $repo, server: false, groups: []}
    let cases = [
        [name env c wants];
        ["assume takes the preset" "" $c [base core desktop programming]]
        ["env names them" "gaming core" $c [base gaming core]]
        ["env repeats base" "base gaming" $c [base gaming]]
        ["server keeps its own" "gaming" ($c | merge {server: true, groups: [base core]}) [base core]]
    ]
    for t in $cases {
        let got = with-env {BOOTSTRAP_ASSUME_YES: "1", BOOTSTRAP_TUI: "", BOOTSTRAP_GROUPS: $t.env} { answer-groups $e $t.c }
        assert equal $got $t.wants $"groups ($t.name): got ($got | to nuon)"
    }
    let unknown = {|| with-env {BOOTSTRAP_ASSUME_YES: "1", BOOTSTRAP_GROUPS: "nonexistent"} { answer-groups $e $c } }
    assert (dies $unknown) "groups: an unknown group must die"
    let universe = platform-groups-all $REPO
    let stale = $e.default | where $it not-in $universe
    assert ($stale | is-empty) $"groups: the preset names ($stale | str join ', '), which configs/ does not have"
}

def marker-cases [repo: path]: nothing -> nothing {
    let marker = $repo | path join marker
    let cases = [
        [name content wants];
        ["no marker" null ""]
        ["armed" $"($STAGE_ESP_RUNNING)\n" running]
        ["stopped" $"($STAGE_ESP_STOPPED)\n" stopped]
        ["empty" "" running]
    ]
    for t in $cases {
        rm --force $marker
        if $t.content != null { $t.content | save $marker }
        let got = stage-marker-state $marker
        assert equal $got $t.wants $"marker ($t.name): got ($got | to nuon)"
    }
}

# The lab is probed only when [lsck0] is there; down, a machine off the lab drops the section, a homelab one dies.
def pacman-conf-cases []: nothing -> nothing {
    let unprobed = {|| error make {msg: "probed without an [lsck0] section"} }
    let cases = [
        [name conf homelab reachable wants];
        ["no section" $PACMAN_PLAIN false $unprobed $PACMAN_PLAIN]
        ["lab up" $PACMAN_LSCK0 false {|| true } $PACMAN_LSCK0]
        ["lab up, homelab" $PACMAN_LSCK0 true {|| true } $PACMAN_LSCK0]
        ["lab down" $PACMAN_LSCK0 false {|| false } $PACMAN_PLAIN]
    ]
    for t in $cases {
        let got = pacman-conf-lsck0 $t.conf $t.homelab $t.reachable
        assert equal $got $t.wants $"pacman.conf ($t.name): got ($got | to nuon)"
    }
    assert (dies {|| pacman-conf-lsck0 $PACMAN_LSCK0 true {|| false } }) "pacman.conf: a homelab machine with the lab down must die"
}

def main [] {
    let repo = fixture
    try { profile-cases $repo; platform-cases $repo; groups-cases $repo; marker-cases $repo; pacman-conf-cases } catch {|e| rm --recursive --force $repo; error make $e }
    rm --recursive --force $repo
}
