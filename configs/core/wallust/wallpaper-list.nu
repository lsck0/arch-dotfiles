#!/usr/bin/env -S nu --no-config-file

use ../../../scripts/lib/state.nu [xdg]
use ../../../scripts/lib/usage.nu [die]

const PUBLIC_DIR = path self ../../../wallpapers
const IMAGE_SUFFIXES = [jpg jpeg png gif webp]
const SCREEN_DEFAULT = "3840x2160"
const CROP_PERCENT_MAX = 10
const UPSCALE_PERCENT_MAX = 105
const CACHE = "wallpaper-list/sizes.tsv"
# the bought ones, synced across machines by syncthing, absent on a machine without ~/sync
const BOUGHT = "sync/wallpapers"

def bought-dir []: nothing -> path { $nu.home-dir | path join $BOUGHT }

def images-in [dir: path]: nothing -> table {
    if not ($dir | path exists) { return [] }
    ls $dir | where type == file and ($it.name | path parse | get extension | str lowercase) in $IMAGE_SUFFIXES
    | each { {path: $in.name, mtime: ($in.modified | into int)} }
}

# ~/sync/wallpapers (bought, private) shadows wallpapers/ by file name.
def wallpapers []: nothing -> table {
    images-in $PUBLIC_DIR | append (images-in (bought-dir))
    | insert name { $in.path | path basename } | reverse | uniq-by name | reject name | sort-by path
}

# Header reads only, cached by mtime: one vipsheader call for every file the cache does not know.
def sizes-of [files: table]: nothing -> table {
    let cache_file = xdg cache $CACHE
    let cached = try {
        open --raw $cache_file | from tsv --noheaders | rename path mtime width height | into int mtime width height
    } catch { [] }
    let known = $files | each {|f| $cached | where path == $f.path and mtime == $f.mtime | get --optional 0 } | compact
    let unknown = $files | where path not-in $known.path
    let read = if ($unknown | is-empty) { [] } else {
        do { ^vipsheader ...$unknown.path } | complete | get stdout | lines
        | parse --regex '^(?<path>.*): (?<width>\d+)x(?<height>\d+) ' | into int width height | join $unknown path
    }
    let sizes = $known ++ $read | sort-by path | select path mtime width height
    $unknown | where path not-in $read.path
    | each { print --stderr $"wallpaper-list: skipping ($in.path): unreadable image" }
    if ($read | is-not-empty) or (($sizes | length) != ($cached | length)) {
        mkdir ($cache_file | path dirname)
        let tmp = $"($cache_file).($nu.pid)"
        $sizes | to tsv --noheaders | save --force $tmp
        mv --force $tmp $cache_file
    }
    $sizes
}

# The file a bare wallpaper name refers to, the bought one first; null when none.
export def wallpaper-resolve [name: string]: nothing -> any {
    if $name == "" or "/" in $name or $name in [. ..] { return null }
    [(bought-dir) $PUBLIC_DIR] | each { path join $name }
    | where { ($in | path type) == file }
    | get --optional 0
}

# Integers only: nu compares floats with a tolerance, which blurs the limits.
def fits-screen [width: int, height: int, screen: record]: nothing -> bool {
    let sides = [($screen.width * $height) ($screen.height * $width)]
    let upscaled = 100 * $screen.width > $UPSCALE_PERCENT_MAX * $width or 100 * $screen.height > $UPSCALE_PERCENT_MAX * $height
    not $upscaled and (100 - $CROP_PERCENT_MAX) * ($sides | math max) <= 100 * ($sides | math min)
}

# List wallpapers a WxH screen shows without visible upscaling or cropping over a tenth, one path per line.
def main [--screen: string, --resolve: string]: nothing -> nothing {
    if $screen != null and $resolve != null { die --misuse "argument --resolve: not allowed with argument --screen" }
    if $resolve != null {
        let path = wallpaper-resolve $resolve
        if $path == null { die $"no wallpaper named ($resolve)" }
        print $path
        return
    }
    let parts = $screen | default $SCREEN_DEFAULT | str lowercase | parse --regex '^(?<width>\d+)x(?<height>\d+)$'
    if ($parts | is-empty) or ($parts.0 | values | any { into int | $in == 0 }) {
        die --misuse $"argument --screen: not WxH: ($screen)"
    }
    let target = $parts.0 | update width { into int } | update height { into int }
    sizes-of (wallpapers) | where { fits-screen $in.width $in.height $target } | each { print $in.path } | ignore
}
