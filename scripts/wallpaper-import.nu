#!/usr/bin/env -S nu --no-config-file

const SCRIPTS = path self | path expand | path dirname
use ($SCRIPTS | path join lib usage.nu) [die]
use ($SCRIPTS | path join lib secrets.nu) [secret-is-plaintext]

const REPO = $SCRIPTS | path dirname
const PUBLIC_DIR = $REPO | path join wallpapers
const SECRET_DIR = $REPO | path join secrets wallpapers
const SECRETS_PROBE = $REPO | path join secrets age.txt
const IMAGE_SUFFIXES = [jpg jpeg png webp]
const FINGERPRINT_SIZE = "32x18!"
# mean absolute grey difference per pixel (0-255) below which two images are the same artwork
const MATCH_DISTANCE_MAX = 12
# grey level (of 255) under which a border row or column counts as letterbox padding
const LETTERBOX_FUZZ = "6.3%"
const THUMBNAIL_SIZE = "1024x1024>"

# letterboxed low-res copies would never match their unpadded originals, so padding is trimmed first
def fingerprint-of [file: path]: nothing -> list<int> {
    (^magick $"($file)[0]" -grayscale Rec601Luma -thumbnail $THUMBNAIL_SIZE
        -bordercolor black -border 1 -fuzz $LETTERBOX_FUZZ -trim +repage
        -filter Lanczos -resize $FINGERPRINT_SIZE -depth 8 gray:-)
    | into binary | chunks 1 | each { into int }
}

def is-image [file: path]: nothing -> bool {
    ($file | path parse | get extension | str lowercase) in $IMAGE_SUFFIXES
}

# Import high-res wallpapers (files, dirs, zips) into secrets/wallpapers/, shadowing matching low-res ones.
def main [...sources: path]: nothing -> nothing {
    if ($sources | is-empty) { die --misuse "the following arguments are required: file|dir|zip" }
    if not (($SECRETS_PROBE | path exists) and (secret-is-plaintext $SECRETS_PROBE)) {
        die "secrets/ is locked, unlock it first"
    }
    let public = ls $PUBLIC_DIR | get name | where { is-image $in }
        | par-each --keep-order { {name: ($in | path basename), fingerprint: (fingerprint-of $in)} }
    let unzipped = mktemp --directory --tmpdir
    let images = $sources | each {|source|
        match ($source | path type) {
            dir => (glob $"($source | path expand)/**/*" | where { ($in | path type) == file } | sort)
            _ if ($source | str lowercase | str ends-with .zip) => {
                let dir = $unzipped | path join ($source | path basename)
                mkdir $dir
                ^bsdtar -xf $source -C $dir
                glob $"($dir)/**/*" | where { ($in | path type) == file }
            }
            _ => [$source]
        }
    } | flatten | where { is-image $in }
    mkdir $SECRET_DIR
    $images | each {|image|
        let candidate = fingerprint-of $image
        let best = $public | each {|p|
            {name: $p.name, distance: ($candidate | zip $p.fingerprint | each { $in.0 - $in.1 | math abs } | math avg)}
        } | sort-by distance | first
        let name = $image | path basename
        let target = if $best.distance <= $MATCH_DISTANCE_MAX { $best.name } else {
            let parts = $name | path parse
            let slug = $parts.stem | str lowercase | str replace --all --regex '[^a-z0-9]+' '-' | str trim --char '-'
            $"($slug).($parts.extension | str lowercase)"
        }
        cp $image ($SECRET_DIR | path join $target)
        let size = ^magick identify -format "%wx%h" $"($image)[0]"
        let how = if $target == $best.name { $"shadows wallpapers/($best.name)" } else { "new, no public match" }
        let distance = $best.distance | into string --decimals 1
        print $"($name)  ($size)  -> secrets/wallpapers/($target)  \(($how), distance ($distance)\)"
    } | ignore
    rm --recursive --force $unzipped
}
