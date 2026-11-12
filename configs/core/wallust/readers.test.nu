#!/usr/bin/env -S nu --no-config-file
# Tools that read a pywal file or key by convention, with no reference to it anywhere in the repo: only this list keeps
# the template that writes it from looking unused.

const HERE = path self | path dirname
const REPO = $HERE | path join ../../..
const TEMPLATES = $HERE | path join templates wal
const WALLUST = $HERE | path join wallust.toml

# reader: who reads it; present: a repo file and a string in it that says the reader is set up; file: what it reads
# from ~/.cache/wal
const READERS = [
    [reader present needle file];
    ["pywal.nvim (programming/nvim colors/wal.lua)" configs/programming/nvim/colors/wal.lua 'require("pywal")' colors-wal.vim]
    ["pywal.nvim lock" configs/programming/nvim/lazy-lock.json '"pywal"' colors-wal.vim]
]

# key: a key the reader requires in that file, checked in its template
const KEYS = [
    [reader present needle file key];
    ["pywalfox (desktop/firefox), refuses colors.json without it" configs/desktop/firefox/mod.nu 'pywalfox update' colors.json '"wallpaper":']
]

def written []: nothing -> list<string> {
    let own = ls $TEMPLATES | get name | path basename
    let targets = open $WALLUST | get templates | values | get target
        | where ($it | str starts-with "@CACHE@/wal/") | each { path basename }
    $own ++ $targets
}

def main [] {
    let have = written
    let missing = $READERS | where {|r|
        let path = $REPO | path join $r.present
        ($path | path exists) and (open --raw $path | str contains $r.needle) and $r.file not-in $have
    }
    if ($missing | is-not-empty) {
        let lines = $missing | each { $"($in.file) for ($in.reader)" } | str join ", "
        error make {msg: $"readers.test: no wallust template writes ($lines)"}
    }
    let keyless = $KEYS | where {|r|
        let path = $REPO | path join $r.present
        let template = $TEMPLATES | path join $r.file
        ($path | path exists) and (open --raw $path | str contains $r.needle) and not (($template | path exists) and (open --raw $template | str contains $r.key))
    }
    if ($keyless | is-not-empty) {
        let lines = $keyless | each { $"($in.key) in ($in.file) for ($in.reader)" } | str join ", "
        error make {msg: $"readers.test: a wallust template lacks ($lines)"}
    }
}
