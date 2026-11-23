#!/usr/bin/env -S nu --no-config-file
use std/assert

const EXTRACT = path self extract.nu
const OVERSIZE = "3G"
const CORRUPT_OFFSET = 34

def extract-run [archive: path, destination: path]: nothing -> record {
    ^nu --no-config-file $EXTRACT $archive $destination | complete
}

# Every refused archive exits non-zero and leaves neither the destination nor a stage behind.
def refused-check [work: path, name: string, archive: path]: nothing -> nothing {
    let out = $work | path join $"out-($name)"
    mkdir $out
    let run = extract-run $archive $out
    assert not equal $run.exit_code 0 $"($name): accepted, stdout: ($run.stdout | str trim)"
    assert equal (ls --all $out | get name | path basename) [] $"($name): left files behind"
}

def main [] {
    let work = mktemp --directory
    try {
        let src = $work | path join src
        mkdir ($src | path join dir)
        "one" | save ($src | path join dir f1)
        "two" | save ($src | path join dir f2)
        let archive = {|name| $work | path join $name }

        ^bsdtar -cf (do $archive good.tar) -C $src dir
        let out = $work | path join out-good
        mkdir $out
        let run = extract-run (do $archive good.tar) $out
        assert equal $run.exit_code 0 $"good.tar failed: ($run.stderr | str trim)"
        assert equal ($run.stdout | str trim) ($out | path join good) "good.tar printed the wrong destination"
        assert equal (open --raw ($out | path join good f1)) "one" "good.tar: dir/f1 not flattened into good/f1"

        ^bsdtar -cf (do $archive traversal.tar) -C $src -s ',^dir,../dir,' dir/f1
        refused-check $work traversal (do $archive traversal.tar)

        ^ln -s f1 ($src | path join dir symlink)
        ^bsdtar -cf (do $archive symlink.tar) -C $src dir/f1 dir/symlink
        refused-check $work symlink (do $archive symlink.tar)

        ^ln ($src | path join dir f2) ($src | path join dir hardlink)
        ^bsdtar -cf (do $archive hardlink.tar) -C $src dir/f2 dir/hardlink
        refused-check $work hardlink (do $archive hardlink.tar)

        let big = $work | path join big
        mkdir $big
        ^truncate -s $OVERSIZE ($big | path join huge)
        ^bsdtar -cSf (do $archive oversize.tar) -C $big huge
        rm --recursive --force $big
        refused-check $work oversize (do $archive oversize.tar)

        ^bsdtar -cf (do $archive empty.tar) -T /dev/null
        refused-check $work empty (do $archive empty.tar)

        ^7z a -bd -y (do $archive corrupt.7z) ($src | path join dir f1) | ignore
        let bytes = open --raw (do $archive corrupt.7z) | into binary
        let flipped = if ($bytes | bytes at $CORRUPT_OFFSET..$CORRUPT_OFFSET) == 0x[00] { 0x[01] } else { 0x[00] }
        ($bytes | bytes at 0..<$CORRUPT_OFFSET) ++ $flipped ++ ($bytes | bytes at ($CORRUPT_OFFSET + 1)..) | save --force --raw (do $archive corrupt.7z)
        refused-check $work corrupt (do $archive corrupt.7z)

        let missing = extract-run (do $archive good.tar) ($work | path join missing)
        assert equal $missing.exit_code 2 "a missing destination must exit 2"
    } catch {|err|
        rm --recursive --force $work
        error make {msg: $err.msg}
    }
    rm --recursive --force $work
}
