#!/usr/bin/env -S nu --no-config-file
# run-records reads what a run file still holds: a line cut off mid-write, garbage, bytes that are no UTF-8 and json
# that is no record are skipped, the records around them kept.
use log.nu [run-records]
use std/assert

const RECORD_FIRST = '{"time":"t","level":"INFO","run":"r","module":"","msg":"first"}'
const RECORD_LAST = '{"time":"t","level":"WARN","run":"r","module":"m","msg":"last"}'

def main []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-log-test.XXXXXX
    let file = $dir | path join run.jsonl
    let cases = [
        [name bytes wants];
        ["whole" ($"($RECORD_FIRST)\n($RECORD_LAST)\n" | into binary) [first last]]
        ["cut off" ($"($RECORD_FIRST)\n($RECORD_LAST | str substring 0..20)" | into binary) [first]]
        ["garbage between" ($"($RECORD_FIRST)\ngarbage\n12\n{}\n($RECORD_LAST)\n" | into binary) [first last]]
        ["no utf-8" ($"($RECORD_FIRST)\n" | into binary | bytes add --end 0x[00 ff 0a]) [first]]
        ["empty" 0x[] []]
    ]
    for c in $cases {
        $c.bytes | save --force --raw $file
        let got = run-records $file | get msg
        assert equal $got $c.wants $"run-records ($c.name): got ($got | to nuon)"
    }
    rm --recursive --force $dir
}
