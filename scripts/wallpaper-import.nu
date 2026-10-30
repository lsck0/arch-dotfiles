#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib log.nu) [log-warn]
use ($SCRIPTS | path join lib usage.nu) [die]

const EXTRACT = $SCRIPTS | path join extract.nu

const REPO = $SCRIPTS | path dirname
const PUBLIC_DIR = $REPO | path join wallpapers
# syncthing carries them to every machine; the user imports them, dot never writes there
const BOUGHT = "sync/wallpapers"
const IMAGE_SUFFIXES = [jpg jpeg png webp]
const FINGERPRINT_SIZE = "32x18!"
const MATCH_DISTANCE_MAX = 12
const LETTERBOX_FUZZ = "6.3%"
const THUMBNAIL_SIZE = "1024x1024>"

def fingerprint-of [file: path]: nothing -> list<int> {
    (^magick $"($file)[0]" -grayscale Rec601Luma -thumbnail $THUMBNAIL_SIZE
        -bordercolor black -border 1 -fuzz $LETTERBOX_FUZZ -trim +repage
        -filter Lanczos -resize $FINGERPRINT_SIZE -depth 8 gray:-)
    | into binary | chunks 1 | each { into int }
}

def is-image [file: path]: nothing -> bool {
    ($file | path parse | get extension | str lowercase) in $IMAGE_SUFFIXES
}

# find, not glob: a dir name like "Pack [4K]" would be read as a pattern and match nothing
def files-under [dir: path]: nothing -> list<path> {
    ^find $dir -type f -print0 | split row (char nul) | where $it != "" | sort
}

# Import high-res wallpapers (files, dirs, zips) into ~/sync/wallpapers/, shadowing matching low-res ones.
def main [...sources: path]: nothing -> nothing {
    if ($sources | is-empty) { die --misuse "the following arguments are required: file|dir|zip" }
    $env.LOG_TAG = "wallpaper-import"
    let bought = $nu.home-dir | path join $BOUGHT
    if not ($bought | path dirname | path exists) { die "~/sync is missing: syncthing is not set up here" }
    let public = ls $PUBLIC_DIR | get name | where { is-image $in }
        | par-each --keep-order { {name: ($in | path basename), fingerprint: (fingerprint-of $in)} }
    let unzipped = mktemp --directory --tmpdir
    try {
        let images = $sources | each {|source|
            let found = match ($source | path type) {
                dir => (files-under ($source | path expand))
                _ if ($source | str lowercase | str ends-with .zip) => {
                    let done = ^$EXTRACT $source $unzipped | complete
                    if $done.exit_code != 0 { error make {msg: ($done.stderr | str trim)} }
                    files-under ($done.stdout | str trim)
                }
                _ => [$source]
            } | where { is-image $in }
            if ($found | is-empty) { log-warn $"no images in ($source)" }
            $found
        } | flatten
        let imports = $images | each {|image|
            let candidate = fingerprint-of $image
            let best = $public | each {|p|
                {name: $p.name, distance: ($candidate | zip $p.fingerprint | each { $in.0 - $in.1 | math abs } | math avg)}
            } | sort-by distance | first
            # $best is null when wallpapers/ holds no images: then every import is new, with no match to compare against
            let matched = $best != null and $best.distance <= $MATCH_DISTANCE_MAX
            let target = if $matched { $best.name } else {
                let parts = $image | path basename | path parse
                let slug = $parts.stem | str lowercase | str replace --all --regex '[^a-z0-9]+' '-' | str trim --char '-'
                $"($slug).($parts.extension | str lowercase)"
            }
            {image: $image, best: $best, matched: $matched, target: $target}
        }
        let clashes = $imports | group-by target | values | where { ($in | length) > 1 }
        if ($clashes | is-not-empty) {
            error make {msg: $"($clashes.0.image | str join ' and ') all map to ~/sync/wallpapers/($clashes.0.0.target)"}
        }
        mkdir $bought
        $imports | each {|i|
            cp $i.image ($bought | path join $i.target)
            let size = ^magick identify -format "%wx%h" $"($i.image)[0]"
            let how = if $i.matched { $"shadows wallpapers/($i.best.name)" } else { "new, no public match" }
            let distance = if $i.best == null { "n/a" } else { $i.best.distance | into string --decimals 1 }
            print $"($i.image | path basename)  ($size)  as ~/sync/wallpapers/($i.target)  \(($how), distance ($distance)\)"
        } | ignore
    } catch {|err|
        rm --recursive --force $unzipped
        die $err.msg
    }
    rm --recursive --force $unzipped
}
