#!/usr/bin/env -S nu --no-config-file --stdin

const DERIVE_ORDER = "Debug,Default,Clone,Copy,PartialEq,Eq,PartialOrd,Ord,Hash,Serialize,Deserialize,..."

# Filter stdin to stdout: reorder a Rust file's #[derive(...)] lists into canonical order.
def main []: string -> nothing {
    let source = $in
    let tmp = mktemp --tmpdir --suffix .rs
    $source | save --force $tmp
    try {
        ^cargo sort-derives --path $tmp --order $DERIVE_ORDER
        print --no-newline (open --raw $tmp)
    } finally { rm --force $tmp }
}
