#!/usr/bin/env -S nu --no-config-file
# "<image>\t<thumb>" per eligible wallpaper; with `themes` a third <theme> column

const SELF = path self

const THUMB_SIZE = "800x800"
const THUMB_QUALITY = 88

def cache-dir []: nothing -> string {
    [($env.XDG_CACHE_HOME? | default ($env.HOME | path join .cache)) quickshell image-picker] | path join
}

def thumb-hash [image: string]: nothing -> string {
    let stat = ls ($image | path expand) | first
    $"($image)\t($stat.size | into int):(($stat.modified | into int) // 1_000_000_000)" | hash md5
}

def row-render [image: string]: nothing -> string {
    let thumb = cache-dir | path join $"((thumb-hash $image)).jpg"
    $"($image)\t(if ($thumb | path exists) { $thumb } else { $image })"
}

def thumbnails-spawn [images: list<string>]: nothing -> nothing {
    if (which vipsthumbnail | is-not-empty) {
        let lock = cache-dir | path join lock
        ^setsid -f flock -n $lock $SELF thumbnails ...$images o+e> /dev/null
    }
}

def "main thumbnails" [...images: string] {
    for image in ($images | where { path exists }) {
        let path = cache-dir | path join $"((thumb-hash $image)).jpg"
        if not ($path | path exists) {
            try {
                let tmp = $"($path).tmp"
                ^vipsthumbnail $image --size $THUMB_SIZE -o $"($tmp)[Q=($THUMB_QUALITY)]"
                mv --force $tmp $path
            }
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
    let rows = glob $"($theme_dir)/*.json" | sort
        | each {|file| {theme: ($file | path parse | get stem), name: (open $file | get wallpaper? | default "")} }
        | where name != "" and not ($it.name | str contains /)
        | each {|t| $t | insert image (wallpaper-resolve $wallpaper_list $t.name) }
        | where image != null
        | uniq-by image
    thumbnails-spawn $rows.image
    $rows | each {|t| print $"(row-render $t.image)\t($t.theme)" } | ignore
}

def main [wallpaper_list: string, screen?: string] {
    mkdir (cache-dir)
    # not qt's devicePixelRatio: it rounds a 1.67 scale to 2, so a 4k panel reads as 4608x2592
    let size = $screen | default (^hyprctl -j monitors | from json | sort-by { $in.width * $in.height } | last | $"($in.width)x($in.height)")
    let images = ^$wallpaper_list --screen $size | lines
    thumbnails-spawn $images
    $images | where { path exists } | each { print (row-render $in) } | ignore
}
