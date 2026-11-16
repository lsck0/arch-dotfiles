#!/usr/bin/env -S nu --no-config-file
# "<image>\t<thumb>\t<theme>\t<artist>" per eligible wallpaper; <theme> is empty unless `themes` lists them

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

# File name to artist from the credits table's author column, which leads with the name up to the title's colon or a
# parenthesis; the file names alone do not say where the artist ends (david-revoy-episode-7, vincent-van-gogh-...).
def artists-load [credits?: string]: nothing -> record {
    if $credits == null or not ($credits | path exists) { return {} }
    open --raw $credits | lines | parse --regex '^\| (?<file>[^| ]+) \| (?<artist>[^|:(]+)'
    | each { [$in.file ($in.artist | str trim)] } | into record
}

# The cached thumbnail, the image itself until thumbnails-spawn has made it.
def thumb-path [image: string]: nothing -> string {
    let thumb = cache-dir | path join $"((thumb-hash $image)).jpg"
    if ($thumb | path exists) { $thumb } else { $image }
}

def row-render [image: string, theme: string, artists: record]: nothing -> string {
    [$image (thumb-path $image) $theme ($artists | get --optional ($image | path basename) | default "")] | str join "\t"
}

def thumbnails-spawn [images: list<string>]: nothing -> nothing {
    if (which vipsthumbnail | is-not-empty) {
        let lock = cache-dir | path join lock
        ^setsid -f flock -n $lock $SELF thumbnails ...$images o+e> /dev/null
    }
}

def "main thumbnails" [...images: string] {
    for image in ($images | where { path exists }) {
        let hash = thumb-hash $image
        let path = cache-dir | path join $"($hash).jpg"
        if not ($path | path exists) {
            try {
                # vipsthumbnail picks the saver from the last suffix
                let tmp = cache-dir | path join $"($hash).tmp.jpg"
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

def "main themes" [theme_dir: string, wallpaper_list: string, credits?: string] {
    mkdir (cache-dir)
    if ($theme_dir | path type) != dir { return }
    let rows = glob $"($theme_dir)/*.json" | sort
        | each {|file| {theme: ($file | path parse | get stem), name: (open $file | get wallpaper? | default "")} }
        | where name != "" and not ($it.name | str contains /)
        | par-each {|t| $t | insert image (wallpaper-resolve $wallpaper_list $t.name) }
        | where image != null
        | sort-by theme
        | uniq-by image
    thumbnails-spawn $rows.image
    let artists = artists-load $credits
    $rows | each {|t| print (row-render $t.image $t.theme $artists) } | ignore
}

# "<theme|wallpaper>\t<pick>\t<thumb>\t<palette>" per pick in dot theme's record of the last ones, themes first: a theme by
# name with its wallpaper's thumbnail and its palette as json, a wallpaper by path
def "main recent" [theme_dir: string, wallpaper_list: string, recent_file: string] {
    mkdir (cache-dir)
    let recent = try { open $recent_file | into record } catch { {} }
    let themes = $recent.themes? | default [] | each {|name|
        let theme = try { open ($theme_dir | path join $"($name).json") } catch { {} }
        let image = wallpaper-resolve $wallpaper_list ($theme.wallpaper? | default "")
        if $image != null { {kind: theme, pick: $name, image: $image, palette: ($theme | select special colors | to json --raw)} }
    } | compact
    let wallpapers = $recent.wallpapers? | default [] | where { path exists }
        | each {|image| {kind: wallpaper, pick: $image, image: $image, palette: ""} }
    let rows = $themes ++ $wallpapers
    thumbnails-spawn ($rows | each { $in.image })
    $rows | each {|r| print ([$r.kind $r.pick (thumb-path $r.image) $r.palette] | str join "\t") } | ignore
}

def main [wallpaper_list: string, credits?: string] {
    mkdir (cache-dir)
    # not qt's devicePixelRatio: it rounds a 1.67 scale to 2, so a 4k panel reads as 4608x2592
    let size = ^hyprctl -j monitors | from json | sort-by { $in.width * $in.height } | last | $"($in.width)x($in.height)"
    let images = ^$wallpaper_list --screen $size | lines | where { path exists }
    thumbnails-spawn $images
    let artists = artists-load $credits
    $images | each { print (row-render $in "" $artists) } | ignore
}
