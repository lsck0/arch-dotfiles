#!/usr/bin/env -S nu --no-config-file
# preserve-aside: a move takes the original away, a copy leaves it on its inode so a write in place reaches every
# hardlink while preserved/ keeps the old content; a second preserve in the same second gets its own name, an absent
# path none, and a copy that fails leaves neither a preserved entry nor its temporary file behind.
use preserve.nu [preserve-aside preserve-dir preserve-copies]
use std/assert

def inode [path: path]: nothing -> string { ^stat -c '%i' $path | str trim }

def preserved-files []: nothing -> list<string> {
    if not (preserve-dir | path exists) { return [] }
    glob $"(preserve-dir)/**/*" --no-dir
}

def move-cases [dir: path]: nothing -> nothing {
    let file = $dir | path join moved
    "old" | save $file
    let dest = preserve-aside $file
    assert not ($file | path exists) "move: the original is still in place"
    assert equal (open --raw $dest) "old" "move: the preserved copy lost its content"
    assert equal (preserve-copies $file) [$dest] "move: preserve-copies does not list it"
    assert equal (preserve-aside ($dir | path join absent)) null "move: an absent path preserved something"
}

def copy-cases [dir: path]: nothing -> nothing {
    let file = $dir | path join copied
    let link = $dir | path join copied-link
    "old" | save $file
    ^ln $file $link
    let before = inode $file
    let first = preserve-aside $file --copy
    assert equal (inode $file) $before "copy: the original changed its inode"
    assert equal (open --raw $first) "old" "copy: the preserved copy lost its content"
    ^sh -c 'printf new > "$1"' sh $file
    assert equal (open --raw $link) "new" "copy: a write in place did not reach the hardlink"
    assert equal (open --raw $first) "old" "copy: a write in place reached the preserved copy"
    let second = preserve-aside $file --copy
    assert ($second != $first) "copy: a second preserve reused the first one's name"
    assert equal (open --raw $second) "new" "copy: the second preserve holds the wrong content"
    let copies = preserve-copies $file
    assert ($first in $copies and $second in $copies) $"copy: preserve-copies lists ($copies | to nuon)"
    let temporary = preserved-files | where ($it | str contains ".dot-new.")
    assert equal $temporary [] "copy: a temporary file is left under preserved/"
}

def failure-cases [dir: path]: nothing -> nothing {
    let unreadable = $dir | path join unreadable
    "secret" | save $unreadable
    chmod 000 $unreadable
    let failed = try { preserve-aside $unreadable --copy; false } catch { true }
    assert $failed "copying an unreadable file counted as preserved"
    let left = preserved-files | where ($it | str contains "unreadable")
    assert equal $left [] "a failed copy left files under preserved/"
    chmod 600 $unreadable
}

def main []: nothing -> nothing {
    let dir = mktemp --directory --tmpdir dot-preserve-test.XXXXXX
    $env.XDG_STATE_HOME = $dir | path join state
    try { move-cases $dir; copy-cases $dir; failure-cases $dir } catch {|e| rm --recursive --force $dir; error make $e }
    rm --recursive --force $dir
}
