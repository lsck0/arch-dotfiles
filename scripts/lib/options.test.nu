#!/usr/bin/env -S nu --no-config-file
# options-nuon-set, the one writer of options and platform files: only the changed entry's lines move, comments and
# quoting stay, a one-line record stays on its line, a record left empty goes, and what the text reads back as is always
# the record with the change applied.
use options.nu [options-nuon-set]
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
        [name cell value wants];
        ["same value, same bytes" [label] "A box" $FILE]
        ["a scalar" [label] "B box" ($FILE | str replace '"A box"' '"B box"')]
        ["a list" [groups] [base] ($FILE | str replace "[base core]" "[base]")]
        ["a nested key" [facts homelab] false ($FILE | str replace "homelab: true" "homelab: false")]
        ["a new nested key" [facts offload] target ($FILE | str replace "        homelab: true\n" "        homelab: true\n        offload: target\n")]
        ["a new top key" [packages_keep] [a] ($FILE | str replace "}\n}\n" "}\n    packages_keep: [a]\n}\n")]
        ["a removed key" [label] null ($FILE | str replace "    label: \"A box\"\n" "")]
        ["a removed missing key" [nix_keep] null $FILE]
        ["a one-line record" ["base/fail2ban" enable] true ($FILE | str replace "{enable: false}" "{enable: true}")]
        ["a one-line record grows" ["base/fail2ban" bantime] 60 ($FILE | str replace "{enable: false}" "{enable: false, bantime: 60}")]
        ["a record left empty" ["base/fail2ban" enable] null ($FILE | str replace "    \"base/fail2ban\": {enable: false}\n" "")]
        ["a new record" ["core/locale" lang] "de_DE.UTF-8" ($FILE | str replace "}\n}\n" "}\n    \"core/locale\": {\n        lang: de_DE.UTF-8\n    }\n}\n")]
    ]
    for c in $cases {
        let got = $FILE | options-nuon-set $c.cell $c.value
        assert equal $got $c.wants $"splice ($c.name): got\n($got)"
    }
    let comment_kept = $FILE | options-nuon-set [facts wireguard] "wireguard/other.conf"
    assert ($comment_kept | str contains "# the lab tunnel") "splice: the comment above a changed key went"
    let emptied = $FILE | options-nuon-set [facts wireguard] null | options-nuon-set [facts homelab] null
    assert equal ($emptied | from nuon | get --optional facts) null $"splice: facts left empty stays\n($emptied)"
}

# Text with no splice to read back as wanted, an empty file and a one-line file, is written whole.
def whole-cases [] {
    assert equal ("" | options-nuon-set [x] 1) "{\n    x: 1\n}\n" "whole: an empty file"
    assert equal ("{a: 1}\n" | options-nuon-set [b] 2) "{\n    a: 1\n    b: 2\n}\n" "whole: a one-line file goes multi-line"
    assert equal ("{\n    a: 1}\n" | options-nuon-set [b] 2 | from nuon) {a: 1, b: 2} "whole: a brace after an entry"
}

def main [] {
    splice-cases
    whole-cases
}
