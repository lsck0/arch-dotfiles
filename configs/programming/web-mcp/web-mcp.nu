#!/usr/bin/env -S nu --no-config-file
# Starts one of web-mcp's servers with its API key read from the secrets at start, so the key never lands in
# ~/.claude.json; the package pins live in mod.nu.

const REPO = path self | path expand | path dirname --num-levels 4
use ($REPO | path join configs programming web-mcp mod.nu) [SERVERS]

def main [name: string]: nothing -> nothing {
    let s = $SERVERS | get --optional $name
    if $s == null { error make --unspanned {msg: $"web-mcp: no server ($name), one of ($SERVERS | columns | str join ' ')"} }
    let key = open --raw ($REPO | path join configs secrets keys $s.key) | str trim
    load-env {($s.env): $key, DO_NOT_TRACK: "1"}
    exec npx -y $s.package
}
