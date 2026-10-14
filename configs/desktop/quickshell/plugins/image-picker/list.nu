#!/usr/bin/env -S nu --no-config-file
# prints "<image>\t<thumbnail or image>" per wallpaper eligible for the largest screen, or with `themes`
# "<image>\t<thumbnail or image>\t<theme>" per theme wallpaper; thumbnails are made afterwards, detached

# a copy under ~/.config/quickshell, not the repo: the repo's wallpaper-list.nu comes in as an argument
const SELF = path self

const THUMB_SIZE = "800x800"
const THUMB_QUALITY = 88

def cache-dir []: nothing -> string {
    [($env.XDG_CACHE_HOME? | default ($env.HOME | path join .cache)) quickshell image-selector] | path join
}

# the index keeps thumbnails stable across runs
def thumb-name [image: string, index: record]: nothing -> record {
    let stat = ls ($image | path expand) | first
    let key = $"($image)\t($stat.size | into int):(($stat.modified | into int) // 1_000_000_000)"
    {key: $key, hash: ($index | get -o $key | default ($key | hash md5))}
}

def index-load []: nothing -> record {
    let file = cache-dir | path join index.tsv
    if ($file | path exists) { open --raw $file | lines | parse -r '^(?<key>.*)\t(?<hash>[^\t]*)$' | transpose -r -d -l } else { {} }
}

def row-render [image: string, index: record]: nothing -> string {
    let thumb = cache-dir | path join $"((thumb-name $image $index).hash).jpg"
    $"($image)\t(if ($thumb | path exists) { $thumb } else { $image })"
}

def thumbnails-spawn [images: list<string>]: nothing -> nothing {
    if (which vipsthumbnail | is-not-empty) {
        ^setsid -f $SELF thumbnails ...$images o+e> /dev/null
    }
}

def "main thumbnails" [...images: string] {
    let index_file = cache-dir | path join index.tsv
    for image in ($images | where { path exists }) {
        let thumb = thumb-name $image {}
        let path = cache-dir | path join $"($thumb.hash).jpg"
        if not ($path | path exists) {
            ^vipsthumbnail $image --size $THUMB_SIZE -o $"($path)[Q=($THUMB_QUALITY)]"
            $"($thumb.key)\t($thumb.hash)\n" | save -a $index_file
        }
    }
}

def wallpaper-resolve [wallpaper_list: string, name: string]: nothing -> any {
    let found = do { ^$wallpaper_list --resolve $name } | complete
    if $found.exit_code == 0 { $found.stdout | str trim } else { null }
}

def "main themes" [theme_dir: string, wallpaper_list: string] {
    mkdir (cache-dir)
    if ($theme_dir | path type) != dir { return }
    let index = index-load
    # themes name their wallpaper by file name; the first theme to claim one wins
    let rows = glob $"($theme_dir)/*.json" | sort
        | each {|file| {theme: ($file | path parse | get stem), name: (open $file | get wallpaper? | default "")} }
        | where name != "" and not ($it.name | str contains /)
        | each {|t| $t | insert image (wallpaper-resolve $wallpaper_list $t.name) }
        | where image != null
        | uniq-by image
    thumbnails-spawn $rows.image
    $rows | each {|t| print $"(row-render $t.image $index)\t($t.theme)" } | ignore
}

def main [wallpaper_list: string, screen?: string] {
    mkdir (cache-dir)
    # not qt's devicePixelRatio: it rounds a 1.67 scale to 2 and made a 4k panel 4608x2592
    let size = $screen | default (^hyprctl -j monitors | from json | sort-by { $in.width * $in.height } | last | $"($in.width)x($in.height)")
    let images = ^$wallpaper_list --screen $size | lines
    let index = index-load
    thumbnails-spawn $images
    $images | where { path exists } | each { print (row-render $in $index) } | ignore
}
