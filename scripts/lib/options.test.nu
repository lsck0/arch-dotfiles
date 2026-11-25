#!/usr/bin/env -S nu --no-config-file
# options-nuon-set, the one writer of options and platform files: only the changed entry's lines move, comments and
# quoting stay, a one-line record stays on its line, a record left empty goes, a null is stored and only --remove drops
# an entry, and what the text reads back as is always the record with the change applied. option-value-errors: a list
# option's choices bound each entry, a pattern a string. options-resolve: no layer turns on a module the one below
# leaves off.
use options.nu [options-nuon-set option-value-errors options-resolve]
use std/assert

const FILE = '{
    hostname: box
    label: "A box"
    groups: [base core]
    facts: {
        # the lab tunnel
        wireguard: wireguard/box.conf
        homelab: true
    }
    "base/fail2ban": {enable: false}
}
'

def splice-cases [] {
    let cases = [
        [name cell value remove wants];
        ["same value, same bytes" [label] "A box" false $FILE]
        ["a scalar" [label] "B box" false ($FILE | str replace '"A box"' '"B box"')]
        ["a list" [groups] [base] false ($FILE | str replace "[base core]" "[base]")]
        ["a nested key" [facts homelab] false false ($FILE | str replace "homelab: true" "homelab: false")]
        ["a new nested key" [facts offload] target false ($FILE | str replace "        homelab: true\n" "        homelab: true\n        offload: target\n")]
        ["a new top key" [packages_keep] [a] false ($FILE | str replace "}\n}\n" "}\n    packages_keep: [a]\n}\n")]
        ["a null stored" [label] null false ($FILE | str replace '"A box"' "null")]
        ["a new nested null" [facts wireguard_peer] null false ($FILE | str replace "        homelab: true\n" "        homelab: true\n        wireguard_peer: null\n")]
        ["a removed key" [label] null true ($FILE | str replace "    label: \"A box\"\n" "")]
        ["a removed missing key" [nix_keep] null true $FILE]
        ["a removed missing nested key" ["core/locale" lang] null true $FILE]
        ["a one-line record" ["base/fail2ban" enable] true false ($FILE | str replace "{enable: false}" "{enable: true}")]
        ["a one-line record grows" ["base/fail2ban" bantime] 60 false ($FILE | str replace "{enable: false}" "{enable: false, bantime: 60}")]
        ["a record left empty" ["base/fail2ban" enable] null true ($FILE | str replace "    \"base/fail2ban\": {enable: false}\n" "")]
        ["a new record" ["core/locale" lang] "de_DE.UTF-8" false ($FILE | str replace "}\n}\n" "}\n    \"core/locale\": {\n        lang: de_DE.UTF-8\n    }\n}\n")]
    ]
    for c in $cases {
        let got = $FILE | options-nuon-set $c.cell $c.value --remove=$c.remove
        assert equal $got $c.wants $"splice ($c.name): got\n($got)"
    }
    let comment_kept = $FILE | options-nuon-set [facts wireguard] "wireguard/other.conf"
    assert ($comment_kept | str contains "# the lab tunnel") "splice: the comment above a changed key went"
    let emptied = $FILE | options-nuon-set [facts wireguard] null --remove | options-nuon-set [facts homelab] null --remove
    assert equal ($emptied | from nuon | get --optional facts) null $"splice: facts left empty stays\n($emptied)"
}

# Text with no splice to read back as wanted, an empty file and a one-line file, is written whole.
def whole-cases [] {
    assert equal ("" | options-nuon-set [x] 1) "{\n    x: 1\n}\n" "whole: an empty file"
    assert equal ("{a: 1}\n" | options-nuon-set [b] 2) "{\n    a: 1\n    b: 2\n}\n" "whole: a one-line file goes multi-line"
    assert equal ("{\n    a: 1}\n" | options-nuon-set [b] 2 | from nuon) {a: 1, b: 2} "whole: a brace after an entry"
}

def choice-cases [] {
    let list = {type: "list<string>", choices: [media mic ssh]}
    assert equal (option-value-errors m k $list [media ssh] f) [] "choices: a list of choices"
    assert equal (option-value-errors m k $list [] f) [] "choices: an empty list"
    assert equal (option-value-errors m k $list [media x] f) ["f: m.k: [x] is not one of [media, mic, ssh]"] "choices: a list entry outside"
    assert equal (option-value-errors m k {type: "string?", choices: [a b]} null f) [] "choices: an unset nullable"
    assert equal (option-value-errors m k {type: string, choices: [a b]} c f) ['f: m.k: "c" is not one of [a, b]'] "choices: a scalar outside"
}

def pattern-cases [] {
    let url = {type: "string?", pattern: '^https?://'}
    assert equal (option-value-errors m k $url "https://a.org" f) [] "pattern: a match"
    assert equal (option-value-errors m k $url null f) [] "pattern: an unset nullable"
    assert equal (option-value-errors m k $url "a.org" f) ['f: m.k: "a.org" does not match ^https?://'] "pattern: a miss"
}

# A module's enable: a layer turns it off, or back on over a layer below that leaves it on; never on where the
# platform's groups leave it out, or from the profile where the platform turns it off.
def enable-cases [] {
    let modules = [
        [id options selected native];
        [base/on {} true []]
        [base/out {} false []]
    ]
    let resolve = {|platform: record, profile: record|
        options-resolve $modules {options_file: p, options: $platform} {options_file: u, options: $profile}
    }
    let fine = do $resolve {"base/on": {enable: false}} {}
    assert equal $fine.errors [] "enable: the platform turns a module off"
    assert equal ($fine.rows | where id == base/on | first | get values.enable) false "enable: off from the platform"
    assert equal (do $resolve {} {"base/on": {enable: false}} | get errors) [] "enable: the profile turns a module off"
    assert equal (do $resolve {"base/on": {enable: true}} {"base/on": {enable: true}} | get errors) [] "enable: on over on"
    assert equal (do $resolve {"base/out": {enable: true}} {} | get errors) [
        "p: base/out.enable is true where the machine leaves it off; add its group to the platform's groups"
    ] "enable: the platform outside its groups"
    assert equal (do $resolve {"base/on": {enable: false}} {"base/on": {enable: true}} | get errors) [
        "u: base/on.enable is true where the machine leaves it off; the profile only turns a module off"
    ] "enable: the profile over the platform's off"
    assert equal (do $resolve {} {"base/out": {enable: true}} | get errors | length) 1 "enable: the profile outside the groups"
}

def main [] {
    splice-cases
    whole-cases
    choice-cases
    pattern-cases
    enable-cases
}
