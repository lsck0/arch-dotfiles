#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib usage.nu) [die]

const ENTRIES_MAX = 200_000
const TOTAL_MAX = 10GiB
const FILE_MAX = 2GiB
const BSDTAR_ROW = '^(?<mode>\S+)\s+\d+\s+\S+\s+\S+\s+(?<size>\d+)\s+\S+\s+\S+\s+\S+ (?<name>.*)$'
# 7z tags a link by name in tar/wim, by a unix mode starting with l in 7z/zip/rar
const SEVENZIP_LINK_KEYS = ["Symbolic Link" "Hard Link" "Link"]
const SEVENZIP_LINK_MODE = '(^|[\s_-])l[r-][w-][xsS-]'

def entries-check [entries: table]: nothing -> nothing {
    let unsafe = $entries | where {|e|
        let parts = $e.name | str replace --all '\' '/' | split row "/"
        $e.name == "" or $parts.0 == "" or ".." in $parts
    }
    if ($unsafe | is-not-empty) { error make {msg: $"unsafe archive path: ($unsafe.0.name)"} }
    let linked = $entries | where link
    if ($linked | is-not-empty) { error make {msg: $"links are not allowed in archives: ($linked.0.name)"} }
    let sizes = $entries.size | into filesize
    if ($entries | length) > $ENTRIES_MAX or ($sizes | any { $in > $FILE_MAX }) or ($sizes | math sum) > $TOTAL_MAX {
        error make {msg: "archive expansion exceeds safety limit"}
    }
}

def sevenzip-extract [archive: path, stage: path]: nothing -> nothing {
    if (which 7z | is-empty) { error make {msg: $"unsupported archive \(install 7z\): ($archive)"} }
    ^7z l -slt -- $archive | split row "\n----------\n" | get --optional 1 | default ""
    | split row "\n\n" | where $it != "" | each { lines | parse "{key} = {value}" | transpose -r -d }
    | each {|e| {
        name: $e.Path
        size: ($e.Size? | default 0 | into int)
        link: (($SEVENZIP_LINK_KEYS | any {|k| ($e | get --optional $k | default "") != "" })
            or ($e.Attributes? | default "") =~ $SEVENZIP_LINK_MODE)
    } }
    | entries-check $in
    ^7z x -y $"-o($stage)" -- $archive | ignore
}

# libarchive first; 7z for what it cannot read (rar5 variants) or decompress (deflate64 zips)
def stage-fill [archive: path, stage: path]: nothing -> nothing {
    let listing = do { ^bsdtar -tvf $archive } | complete
    if $listing.exit_code != 0 {
        sevenzip-extract $archive $stage
    } else {
        $listing.stdout | lines | parse --regex $BSDTAR_ROW
        | each {|e| {name: $e.name, size: $e.size, link: ($e.mode starts-with l or $e.name =~ " link to ")} }
        | into int size
        | entries-check $in
        if (do { ^bsdtar -xof $archive -C $stage } | complete).exit_code != 0 {
            ls --all $stage | each { rm --recursive --force $in.name } | ignore
            sevenzip-extract $archive $stage
        }
    }
    # whatever a listing missed: a link in the stage fails the whole extract
    if (^find $stage "(" -type l -o -type f -links +1 ")" -print -quit | is-not-empty) {
        error make {msg: $"links are not allowed in archives: ($archive)"}
    }
}

# Safely extract a supported archive into a same-named directory, printing its path.
def main [archive: path, destination?: path]: nothing -> nothing {
    if ($archive | path expand | path type) != file { die --misuse $"not a regular file: ($archive)" }
    let archive = $archive | path expand
    # a compressed tar's two suffixes count as one: linux-6.1.tar.xz is linux-6.1
    let base = $archive | path basename | str replace --regex '(\.tar\.(gz|bz2|xz|zst)|\.[^.]*)$' ''
    let root = $destination | default $env.PWD | path expand
    let dest = $root | path join $base
    if ($dest | path exists) { die $"destination already exists: ($dest)" }
    # next to the destination, not in /tmp: tmpfs is ram, and a big archive staged there would be written twice
    let stage = mktemp --directory --tmpdir-path $root .extract.XXXXXX
    try { stage-fill $archive $stage } catch {|err|
        rm --recursive --force $stage
        die $err.msg
    }
    let entries = ls --all $stage
    let roots = if ($entries | length) == 1 and $entries.0.type == dir { ls --all $entries.0.name } else { $entries }
    mkdir $dest
    if ($roots | is-not-empty) { mv ...$roots.name $dest }
    rm --recursive --force $stage
    print $dest
}
