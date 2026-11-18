#!/usr/bin/env -S nu --no-config-file
# art-accent.nu on generated covers: a solid colour, a grey cover with a small blue patch, a black one; and the cache
# answering the second call for the same image content.

const ART_ACCENT = path self art-accent.nu
const BLUE = "#2050E0"

def fail [msg: string] { error make {msg: $"art-accent.test: ($msg)"} }

def accent [file: path, cache: path]: nothing -> string {
    let run = ^nu --no-config-file $ART_ACCENT --cache-dir $cache $file | complete
    if $run.exit_code != 0 { fail $"($file | path basename) exited ($run.exit_code): ($run.stderr)" }
    $run.stdout
}

def expect [name: string, actual: string, expected: string] {
    if $actual != $expected { fail $"($name): expected '($expected)', got '($actual)'" }
}

def main [] {
    if (which magick | is-empty) { print -e "art-accent.test.nu: warn: skipped, missing magick"; return }
    let dir = mktemp --directory --tmpdir art-accent-XXXXXX
    let outcome = try {
        let cache = $dir | path join cache
        let red = $dir | path join red.png
        let grey_blue = $dir | path join grey-blue.png
        let black = $dir | path join black.png
        ^magick -size 100x100 xc:#FF0000 $red
        ^magick -size 100x100 xc:#808080 -fill $BLUE -draw "rectangle 10,10 39,39" $grey_blue
        ^magick -size 100x100 xc:#000000 $black

        expect "solid red" (accent $red $cache) "#FF0000"
        expect "grey with a blue patch" (accent $grey_blue $cache) $BLUE
        expect "pure black" (accent $black $cache) ""
        expect "missing file" (accent ($dir | path join none.png) $cache) ""

        let entry = $cache | path join (open --raw $red | hash md5)
        "#123456" | save --force $entry
        expect "cached per content" (accent $red $cache) "#123456"
        null
    } catch {|e| $e.msg }
    rm --recursive --force $dir
    if $outcome != null { error make {msg: $outcome} }
}
