#!/usr/bin/env -S nu --no-config-file --stdin

const IMAGE_MIMES = [image/png image/jpeg image/webp image/gif image/bmp image/tiff]
const TEXT_MIMES = [UTF8_STRING STRING]
const PASSWORD_HINT = "x-kde-passwordManagerHint"
const PASS_SLEEPER = "^password store sleep on display"
const PASS_SLEEPER_SETTLE = 200ms
const PASS_SLEEPER_AGE_MAX_S = 1
const IMAGE_FETCH_TIMEOUT = "2s"
# utf-16 without a bom: at least three quarters of the units carry a nul byte, all on one side
const NUL_SHARE_MIN = 0.75
const NUL_SHARE_OTHER_MAX = 0.25
const CONTROL_CHARS = '[\x00-\x08\x0E-\x1A\x1C-\x1F]'

def text-emit []: binary -> nothing {
    let raw = $in
    let size = $raw | bytes length
    if $size == 0 { return }
    let units = $size / 2
    let has_bom = [0x[FFFE] 0x[FEFF]] | any {|bom| $raw | bytes starts-with $bom }
    let nuls = if not $has_bom and $size mod 2 == 0 {
        $raw | encode hex | parse -r '(?<even>..)(?<odd>..)' | {even: ($in | where even == "00" | length), odd: ($in | where odd == "00" | length)}
    }
    let encoding = if $has_bom {
        "utf-16le"
    } else if $nuls != null and ($nuls.even + $nuls.odd) >= $units * $NUL_SHARE_MIN {
        if $nuls.odd >= $units * $NUL_SHARE_MIN and $nuls.even < $units * $NUL_SHARE_OTHER_MAX {
            "utf-16le"
        } else if $nuls.even >= $units * $NUL_SHARE_MIN and $nuls.odd < $units * $NUL_SHARE_OTHER_MAX {
            "utf-16be"
        }
    }
    # encoding_rs sniffs a bom itself, so utf-16le stands for either byte order then
    let utf16 = if $encoding != null { $raw | decode $encoding }
    let text = if $utf16 != null and ($has_bom or $utf16 !~ $CONTROL_CHARS) { $utf16 } else { $raw | decode utf-8 }
    {type: text, text: $text} | to json -r | print
}

def image-emit [mime: string, dir: string]: binary -> nothing {
    let raw = $in
    if ($raw | bytes length) == 0 { return }
    let path = [$dir $"($raw | hash sha256).($mime | str replace image/ '' | str replace jpeg jpg)"] | path join
    if not ($path | path exists) { $raw | save $path }
    {type: image, mime: $mime, path: $path, capturedAt: (date now | format date "%A %H:%M")} | to json -r | print
}

def main [mime?: string] {
    # only the watch modes get the offer on stdin; the bare call must not wait on it
    let input = if $mime != null { $in | into binary }
    # tmpfs: a copied secret never reaches the disk or a backup
    let image_dir = [($env.XDG_RUNTIME_DIR? | default $"/run/user/(^id -u)") quickshell clipboard-images] | path join
    mkdir $image_dir

    let types = ^wl-paste --list-types | complete | get stdout | lines
    if $env.CLIPBOARD_STATE? == "sensitive" or $PASSWORD_HINT in $types { return }

    # pass -c starts its clearing sleeper right after a plain wl-copy: only a fresh one marks this offer as a secret
    sleep $PASS_SLEEPER_SETTLE
    let sleepers = ^pgrep -u (^id -u) -f $PASS_SLEEPER | complete | get stdout | lines
    if ($sleepers | is-not-empty) and (^ps -o etimes= -p ($sleepers | str join ",") | lines | any { into int | $in <= $PASS_SLEEPER_AGE_MAX_S }) {
        return
    }

    match $mime {
        "text" => { $input | text-emit }
        $m if $m != null and ($m starts-with image/) => { $input | image-emit $m $image_dir }
        _ => {
            let image = $IMAGE_MIMES | where $it in $types | get 0?
            if $image != null {
                ^timeout $IMAGE_FETCH_TIMEOUT wl-paste --type $image | complete | get stdout | into binary | image-emit $image $image_dir
            } else if ($types | any { $in starts-with text/ or $in in $TEXT_MIMES }) {
                ^wl-paste --type text --no-newline | complete | get stdout | into binary | text-emit
            }
        }
    }
}
