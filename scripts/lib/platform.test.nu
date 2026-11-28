#!/usr/bin/env -S nu --no-config-file
# A platform file's validation, the one platform-load and the lint apply and dot set checks each write against: known
# keys and facts, typed values and choices, groups that exist; and the keys as the settings window lists them.
use platform.nu [platform-errors platform-value-errors platform-spec platform-cells platform-rows]
use std/assert

# How dot set lands a platform key: live is stored and read where it is used, apply waits for the next dot apply (both
# layers), packages for the next dot apply --packages.
const PLATFORM_APPLY = [live apply packages]

def scratch-repo []: nothing -> path {
    let repo = mktemp --directory --tmpdir dot-platform-test-XXXXXX
    mkdir ($repo | path join configs base) ($repo | path join configs core) ($repo | path join configs secrets) ($repo | path join configs programming docker)
    "" | save ($repo | path join configs programming docker mod.nu)
    $repo
}

def errors-cases [repo: path] {
    let cases = [
        [name raw wants];
        ["the repo's shape" {hostname: box, label: "A box", form_factor: laptop, groups: [base programming/docker], extra_packages: [it87-dkms-git], facts: {homelab: true, wireguard: wireguard/box.conf, offload: client}} 0]
        ["nothing" {} 0]
        ["unknown key" {colour: red} 1]
        ["unknown fact" {facts: {colour: red}} 1]
        ["facts no record" {facts: [homelab]} 1]
        ["form factor" {form_factor: tablet} 1]
        ["label type" {label: 3} 1]
        ["group missing" {groups: [base nope]} 1]
        ["secrets is no group" {groups: [secrets]} 1]
        ["group a module" {groups: [programming/docker]} 0]
        ["groups empty" {groups: []} 1]
        ["package list empty" {extra_packages: []} 0]
        ["package with a blank" {extra_packages: ["a b"]} 1]
        ["package no string" {packages_keep: [1]} 1]
        ["fact type" {facts: {homelab: "yes"}} 1]
        ["fact choice" {facts: {offload: server}} 1]
        ["fact unset" {facts: {offload: null, wireguard: null, lsck0_snapshot: null}} 0]
        ["fact pattern" {facts: {lsck0_snapshot: "2026-11-01"}} 0]
        ["fact off pattern" {facts: {lsck0_snapshot: latest}} 1]
        ["two bad keys" {label: 3, form_factor: tablet} 2]
    ]
    for c in $cases {
        let got = platform-errors $repo $c.raw f.nuon
        assert equal ($got | length) $c.wants $"errors ($c.name): ($got | to nuon)"
        assert ($got | all { str starts-with "f.nuon: " }) $"errors ($c.name): a line without its file: ($got | to nuon)"
    }
    let named = platform-value-errors $repo [facts offload] server "dot set" | first
    assert ($named | str contains "platform.facts.offload") $"errors: the target is not named: ($named)"
}

def spec-cases [] {
    assert equal (platform-spec [hostname]).fixed true "spec: hostname is fixed"
    assert equal (platform-spec [facts homelab]).group facts "spec: a fact sits under facts"
    assert equal (platform-spec [facts homelab]).apply apply "spec: a fact waits for dot apply"
    assert equal (platform-spec [extra_packages]).apply packages "spec: packages wait for dot apply --packages"
    for missing in [[facts] [nope] [facts nope] [label x]] {
        assert equal (platform-spec $missing) null $"spec: ($missing | to nuon) is no key"
    }
    let cells = platform-cells
    assert ([facts homelab] in $cells) "cells: the facts are listed"
    assert ([facts] not-in $cells) "cells: facts itself is no key"
    assert ($cells | all {|c| (platform-spec $c) != null }) "cells: a listed key has no spec"
    let applies = $cells | each {|c| (platform-spec $c).apply } | uniq
    assert ($applies | all { $in in $PLATFORM_APPLY }) $"cells: an apply dot set does not know: ($applies | to nuon)"
}

def rows-cases [repo: path] {
    let file = $repo | path join box.nuon
    {hostname: box, groups: [core programming/docker], facts: {homelab: true}} | save $file
    let rows = with-env {FORM_FACTOR: laptop} { platform-rows $repo {file: $file} }
    let row = {|key| $rows | where key == $key | first }
    assert equal ($rows | length) (platform-cells | length) "rows: one per key"
    assert equal ((do $row groups) | select value source) {value: [core programming/docker], source: platform} "rows: groups as set"
    assert equal (do $row groups).choices [base core programming programming/docker] "rows: groups choose among the groups and the set modules"
    assert equal (do $row groups).default [base core programming] "rows: unset groups are all of them"
    assert (do $row groups).nonempty "rows: the window keeps one group"
    assert equal ((do $row form_factor) | select value source) {value: laptop, source: default} "rows: form factor falls back"
    assert equal ((do $row facts.homelab) | select value source) {value: true, source: platform} "rows: a fact as set"
    assert equal ((do $row facts.offload) | select value source) {value: null, source: default} "rows: an unset fact"
}

def main [] {
    let repo = scratch-repo
    let err = try { errors-cases $repo; spec-cases; rows-cases $repo; null } catch {|e| $e.msg }
    rm --recursive --force $repo
    if $err != null { error make {msg: $err} }
}
