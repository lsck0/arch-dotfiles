#!/usr/bin/env -S nu --no-config-file
# text-render replaces every @key@ and leaves the rest; sqlite-snapshot copies a database whole and identically on a
# second run; file-lines drops blank lines and answers none for a missing file.
use state.nu [text-render sqlite-snapshot file-lines tmp-dir-run]
use std/assert

def render-cases []: nothing -> nothing {
    let cases = [
        [name template values wants];
        ["every occurrence" "@A@-@A@" {A: x} "x-x"]
        ["a number" "port @PORT@" {PORT: 53} "port 53"]
        ["an unknown key stays" "@A@ @B@" {A: 1} "1 @B@"]
        ["no values" "@A@" {} "@A@"]
        ["a dollar in the value" "@A@" {A: "$1"} "$1"]
    ]
    for c in $cases { assert equal ($c.template | text-render $c.values) $c.wants $c.name }
}

def snapshot-cases [work: path]: nothing -> nothing {
    let db = $work | path join live.db
    let copy = $work | path join saved copy.db
    ^sqlite3 $db "create table t (v text); insert into t values ('a');"
    sqlite-snapshot $db $copy
    assert equal (^sqlite3 $copy "select v from t" | str trim) a "the copy's rows"
    let first = open --raw $copy | hash sha256
    sqlite-snapshot $db $copy
    assert equal (open --raw $copy | hash sha256) $first "an unchanged database copies identically"
    assert (not ($"($copy).new" | path exists)) "the fresh file is renamed over the copy"
}

def lines-cases [work: path]: nothing -> nothing {
    let file = $work | path join list
    "a\n\n  \nb\n" | save $file
    assert equal (file-lines $file) [a b] "blank lines"
    assert equal (file-lines ($work | path join missing)) [] "a missing file"
}

def main []: nothing -> nothing {
    render-cases
    tmp-dir-run {|work| snapshot-cases $work; lines-cases $work }
}
