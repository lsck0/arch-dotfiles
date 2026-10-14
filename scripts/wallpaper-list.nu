#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib usage.nu) [die]
use ($SCRIPTS | path join lib secrets.nu) [secret-is-plaintext]

const PUBLIC_DIR = $SCRIPTS | path dirname | path join wallpapers
const SECRET_DIR = $SCRIPTS | path dirname | path join secrets wallpapers
const IMAGE_SUFFIXES = [jpg jpeg png gif webp]
const SCREEN_DEFAULT = "3840x2160"
# filling a screen crops what does not fit; more than this and the picture loses its composition
const CROP_PERCENT_MAX = 10
# upscaling by this little is invisible; beyond it the picture turns soft
const UPSCALE_PERCENT_MAX = 105
const CACHE = ".cache/wallpaper-list/sizes.tsv"

def images-in [dir: path]: nothing -> table {
    if not ($dir | path exists) { return [] }
    ls $dir | where type == file and ($it.name | path parse | get extension | str lowercase) in $IMAGE_SUFFIXES
    | each { {path: $in.name, mtime: ($in.modified | into int)} }
}

# secrets/wallpapers shadows wallpapers/ by file name, a secret only while it is plaintext (git-crypt unlocked)
def wallpapers []: nothing -> table {
    images-in $PUBLIC_DIR | append (images-in $SECRET_DIR | where { secret-is-plaintext $in.path })
    | insert name { $in.path | path basename } | reverse | uniq-by name | reject name | sort-by path
}

# header reads only, cached by mtime, one vipsheader for every file the cache does not know
def sizes-of [files: table]: nothing -> table {
    let cache_file = $nu.home-dir | path join $CACHE
    # a missing or torn cache only costs a rescan
    let cached = try {
        open --raw $cache_file | from tsv --noheaders | rename path mtime width height | into int mtime width height
    } catch { [] }
    let known = $files | each {|f| $cached | where path == $f.path and mtime == $f.mtime | get --optional 0 } | compact
    let unknown = $files | where path not-in $known.path
    let read = if ($unknown | is-empty) { [] } else {
        do { ^vipsheader ...$unknown.path } | complete | get stdout | lines
        | parse --regex '^(?<path>.*): (?<width>\d+)x(?<height>\d+) ' | into int width height | join $unknown path
    }
    let sizes = $known ++ $read | sort-by path
    $unknown | where path not-in $read.path
    | each { print --stderr $"wallpaper-list: skipping ($in.path): unreadable image" }
    mkdir ($cache_file | path dirname)
    # written aside and renamed, so a concurrent run never reads half a file
    let tmp = $"($cache_file).($nu.pid)"
    $sizes | to tsv --noheaders | save --force $tmp
    mv --force $tmp $cache_file
    $sizes
}

# wallpaper-resolve <name>: the path a bare file name resolves to, secrets first, or null
export def wallpaper-resolve [name: string]: nothing -> any {
    if $name == "" or "/" in $name or $name in [. ..] { return null }
    [$SECRET_DIR $PUBLIC_DIR] | each { path join $name }
    | where { ($in | path type) == file and ($in starts-with $PUBLIC_DIR or (secret-is-plaintext $in)) }
    | get --optional 0
}

# integers only: nu compares floats with a tolerance, which blurs the limits
def fits-screen [width: int, height: int, screen: record]: nothing -> bool {
    let sides = [($screen.width * $height) ($screen.height * $width)]
    let upscale = $UPSCALE_PERCENT_MAX
    let upscaled = 100 * $screen.width > $upscale * $width or 100 * $screen.height > $upscale * $height
    not $upscaled and (100 - $CROP_PERCENT_MAX) * ($sides | math max) <= 100 * ($sides | math min)
}

# List the wallpapers worth showing on a screen of WxH physical pixels, one path per line: left out is what would
# visibly upscale or crop away more than a tenth of its area. --resolve prints the path a bare file name resolves to,
# secrets first, unfiltered by screen.
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
