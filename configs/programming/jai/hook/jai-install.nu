#!/usr/bin/env -S nu --no-config-file
# jai + jails from the newest ~/sync/vendor beta zip; a no-op unless the zip is new

const DOT = path self | path dirname | path join .. .. .. .. scripts dot.nu
const JAILS_URL = "https://github.com/SogoCZE/Jails.git"
# built and run as luca, so a pinned commit; bump by hand
const JAILS_COMMIT = "42fa76c816ad34c9f24a4bde586d145c992dc860"

export def jai-zip []: nothing -> any {
    let zips = glob ($nu.home-dir | path join sync vendor "jai-*.zip")
    if ($zips | is-empty) { return null }
    $zips | str join "\n" | ^sort -V | lines | last
}

# the plain names on PATH: `jai` as the compiler's docs and jails' own fallback call it (the beta ships only jai-linux)
def bins-link [dir: path]: nothing -> nothing {
    ^ln -sfn jai-linux ($dir | path join bin jai)
    ^ln -sfn ($dir | path join jails bin jails) ($dir | path join bin jails)
}

def main []: nothing -> nothing {
    let zip = jai-zip
    if $zip == null { return }
    # ~/.jai is a link into the data dir (base/xdg): work in its target, never replace the link
    let dir = $nu.home-dir | path join .jai | path expand
    let stamp = $dir | path join .installed-from
    let name = $zip | path basename
    if ($stamp | path exists) and (open --raw $stamp | str trim) == $name {
        bins-link $dir
        return
    }
    if ($dir | path exists) and not ($stamp | path exists) {
        mv $dir $"($dir).pre-dotfiles-(date now | format date '%Y%m%d%H%M%S')"
        print -e $"jai: kept the existing ($dir) aside"
    }
    rm --recursive --force $dir
    mkdir $dir
    # the zip holds a single top-level jai/ dir
    ^unzip -q $zip -d $dir
    ls ($dir | path join jai) | each { mv $in.name $dir } | ignore
    rm ($dir | path join jai)
    ^$DOT fetch git $JAILS_URL $JAILS_COMMIT ($dir | path join jails)
    do { cd ($dir | path join jails); ^($dir | path join bin jai-linux) build.jai }
    bins-link $dir
    $"($name)\n" | save --force $stamp
}
