#!/usr/bin/env -S nu --no-config-file
# Table cases for the nushell pitfalls lint: what each pattern flags, and the lines it must leave alone.
use gate.nu [nu-pitfalls-find shebang]

def fail [msg: string] { error make {msg: $"gate.test: ($msg)"} }

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
        if $got != $c.wants { fail $"($c.name): got lines ($got | to nuon), wants ($c.wants | to nuon)" }
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
        if $got != $c.wants { fail $"shebang, ($c.name): got ($got | to nuon), wants ($c.wants | to nuon)" }
    }
}

def main [] {
    pitfalls-check
    shebang-check
}
