use module.nu *
use ../../core/nas/scripts/vendor.nu [nas-vendor-dir nas-vendor-newer nas-vendor-newest]

# volatile: a newer jai zip on the NAS is no local input
export const meta = {packages: {pacman: [unzip]}, volatile: true}

const ZIP_GLOB = "jai-*.zip"
const STAMP = ".installed-from"
const DOT = path self ../../../scripts/dot.nu
const JAILS_URL = "https://github.com/SogoCZE/Jails.git"
const JAILS_COMMIT = "42fa76c816ad34c9f24a4bde586d145c992dc860" # committed 2026-09-09

# ~/.jai links into the data dir (base/xdg): work in its target, never replace the link
def jai-dir []: nothing -> path { $nu.home-dir | path join .jai | path expand }

# The plain names on PATH: `jai` as the compiler's docs and jails call it (the beta ships only jai-linux).
def bins-link [dir: path]: nothing -> nothing {
    ^ln -sfn jai-linux ($dir | path join bin jai)
    ^ln -sfn ($dir | path join jails bin jails) ($dir | path join bin jails)
}

export def jai-install [zip: string]: nothing -> nothing {
    let dir = jai-dir
    let stamp = $dir | path join $STAMP
    if ($dir | path exists) and not ($stamp | path exists) {
        mv $dir $"($dir).pre-dotfiles-(date now | format date '%Y%m%d%H%M%S')"
        print -e $"jai: kept the existing ($dir) aside"
    }
    rm --recursive --force $dir
    mkdir $dir
    ^unzip -q $zip -d $dir
    ls --all ($dir | path join jai) | each { mv $in.name $dir } | ignore
    rm ($dir | path join jai)
    ^$DOT internal fetch git $JAILS_URL $JAILS_COMMIT ($dir | path join jails)
    do { cd ($dir | path join jails); ^($dir | path join bin jai-linux) build.jai }
    bins-link $dir
    $"($zip | path basename)\n" | save --force $stamp
}

export def jai-bins-link []: nothing -> nothing { bins-link (jai-dir) }

export def link [cfg: record] {
    if not (owner-unlocked) {
        if (profile-has secrets) { log-warn "jai: secrets locked" }
        return []
    }
    let dir = jai-dir
    let stamp = $dir | path join $STAMP
    let installed = if ($dir | path join bin jai-linux | path exists) { file-trim $stamp } else { "" }
    let vendor = nas-vendor-dir
    let zip = nas-vendor-newest $vendor $ZIP_GLOB
    let name = if $zip == null { "" } else { $zip | path basename }
    let newer = nas-vendor-newer $installed $name
    if $vendor == null {
        log-note $"jai: the NAS vendor dir is not reachable, (if $installed == '' { 'jai not installed' } else { $'keeping ($installed)' })"
    }
    [
        (if $newer { step jai-install $zip --key $name --creates $stamp --network })
        (if $installed != "" and not $newer { step jai-bins-link --done=($dir | path join bin jai | path exists) })
    ]
}
