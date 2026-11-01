#!/usr/bin/env -S nu --no-config-file
# Table cases for the nushell pitfalls lint (what each pattern flags, and the lines it must leave alone) and the
# fail-closed lint.
use gate.nu [nu-pitfalls-find shebang fail-closed-find FAIL_CLOSED]
use std/assert

const REPO = path self ../..

def pitfalls-check [] {
    let cases = [
        [name text wants];
        ["else on its own line" "if $a {\n    1\n}\nelse {\n    2\n}" [4]]
        ["else indented on its own line" "    }\n    else if $b { 2 }" [2]]
        ["else after the brace" "if $a { 1 } else { 2 }" []]
        ["else in a comment" "# else here is prose" []]
        ["elsewhere" "let elsewhere = 1" []]
        # split, or this file trips the rule it tests
        ["exec with a caret" ("exec " + "^hyprland") [1]]
        ["clean" "let x = 1\nprint $x" []]
    ]
    for c in $cases {
        let got = nu-pitfalls-find $c.text | get --optional n | default []
        assert equal $got $c.wants $"($c.name): got lines ($got | to nuon), wants ($c.wants | to nuon)"
    }
}

# A read that ends inside a multi-byte character past the first line still shows the shebang.
def shebang-check [] {
    let cut = "#!/usr/bin/env -S nu --no-config-file\n# Gr" | into binary | bytes add --end 0x[c3]
    let cases = [
        [name head wants];
        ["cut after the first line" $cut "#!/usr/bin/env -S nu --no-config-file"]
        ["one line" ("#!/bin/sh" | into binary) "#!/bin/sh"]
        ["no shebang" ("# a comment\n" | into binary) ""]
        ["empty" 0x[] ""]
    ]
    for c in $cases {
        let got = shebang $c.head
        assert equal $got $c.wants $"shebang, ($c.name): got ($got | to nuon), wants ($c.wants | to nuon)"
    }
}

def fail-closed-check [] {
    let old = "let tor = $TOR | path exists\n(if $policy == lockdown-tor and $tor {\n    unit-enable fw-egress.service\n} else {\n    unit-disable fw-egress.service --now\n})"
    let cases = [
        [name code wants];
        ["policy only" "if $policy != lockdown-tor {\n    ok systemctl stop fw-egress.service | ignore\n}" 0]
        ["enabled, never off" "(unit-enable fw-egress.service)" 0]
        ["off on the path" "const TOR = \"/usr/bin/tor\"\nif not ($TOR | path exists) {\n    ok systemctl stop fw-egress.service\n}" 1]
        ["off through a let and an else" $"const TOR = \"/usr/bin/tor\"\n($old)" 1]
        ["const list on one line" "const UNITS = [fw-lockdown.service fw-egress.service]\nif (which tor | is-empty) { $UNITS | each {|u| unit-disable $u } }" 1]
        ["const list over lines" "const UNITS = [fw-egress.service]\nif (which tor | is-empty) {\n    $UNITS | each {|u|\n        unit-mask $u\n    }\n}" 1]
        ["gate only in comments" "# fw-egress stays on without /usr/bin/tor\nif $policy != lockdown-tor { unit-disable fw-egress.service } # not on which tor" 0]
        ["gate elsewhere in the file" "const TOR = \"/usr/bin/tor\"\nif ($TOR | path exists) { start-tor }\nif $policy == off { unit-disable fw-egress.service }" 0]
        ["another unit off" "if (which tor | is-empty) { unit-disable fw-inbound.service }\n(unit-enable fw-egress.service)" 0]
    ]
    for c in $cases {
        let got = fail-closed-find $REPO [{file: configs/base/nftables/mod.nu, text: $c.code}] | length
        assert equal $got $c.wants $"fail closed, ($c.name): ($got) findings, wants ($c.wants)"
    }
    let empty = mktemp --directory --tmpdir dot-fail-closed-test-XXXXXX
    let lost = fail-closed-find $empty [] | length
    rm --recursive --force $empty
    assert equal $lost ($FAIL_CLOSED | length) $"fail closed, no escape files: ($lost) findings, wants ($FAIL_CLOSED | length)"
}

def main [] {
    pitfalls-check
    shebang-check
    fail-closed-check
}
