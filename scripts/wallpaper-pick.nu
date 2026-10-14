#!/usr/bin/env -S nu --no-config-file --stdin

const THUMB_DIR = ".cache/wal/wallpaper-thumbs"
const THUMB_SIZE_PX = "480"
const RANDOM = "random"

# a cached vipsthumbnail keyed by mtime and size, so a replaced file gets a new one; chafa over the full image would
# decode megapixels on every cursor move
def thumb-of [file: path]: nothing -> path {
    let dir = $nu.home-dir | path join $THUMB_DIR
    let name = $file | path basename
    let stat = ls --long $file | first
    let mtime = $stat.modified | into int | $in // 1_000_000_000
    let thumb = $dir | path join $"($name).($mtime)-($stat.size | into int).jpg"
    if not ($thumb | path exists) {
        mkdir $dir
        ls $dir | get name
        | where { ($in | path basename | str starts-with $"($name).") and ($in | str ends-with .jpg) }
        | each { rm --force $in } | ignore
        do { ^vipsthumbnail $file -s $THUMB_SIZE_PX -o $"($thumb)[Q=80]" } | complete | ignore
    }
    if ($thumb | path exists) { $thumb } else { $file }
}

# Read wallpaper paths on stdin, pick one in fzf with a thumbnail preview, print its path ("random" picks any).
def main []: string -> nothing {
    let wallpapers = $in | lines | where $it != ""
    if ($wallpapers | is-empty) { exit 1 }
    let self = $env.CURRENT_FILE | path expand
    let picked = try {
        $wallpapers | append $RANDOM | str join "\n"
        | (^fzf --prompt "wallpaper> " --delimiter / --with-nth=-1
            --preview-window "right:60%" --preview $"'($self)' preview {}")
        | str trim
    } catch { return }
    print (if $picked == $RANDOM { $wallpapers | shuffle | first } else { $picked })
}

# The fzf preview pane: a thumbnail of the wallpaper.
def "main preview" [wallpaper: string]: nothing -> nothing {
    if $wallpaper == $RANDOM {
        print "(random)"
    } else {
        ^chafa $"--size=($env.FZF_PREVIEW_COLUMNS)x($env.FZF_PREVIEW_LINES)" (thumb-of $wallpaper)
    }
}
