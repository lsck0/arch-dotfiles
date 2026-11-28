use module.nu *
use ../../core/nas/scripts/vendor.nu [NAS_VENDOR_STAMP nas-vendor-dir nas-vendor-plan nas-vendor-set-aside]

# volatile: a newer jai zip on the NAS is no local input
export const meta = {packages: {pacman: [unzip]}, volatile: true}

const ZIP_GLOB = "jai-*.zip"
const DOT = path self ../../../scripts/dot.nu
const JAILS_URL = "https://github.com/SogoCZE/Jails.git"
const JAILS_COMMIT = "42fa76c816ad34c9f24a4bde586d145c992dc860" # committed 2026-09-09

# base/xdg links ~/.jai here only once bin/jai exists: a fresh install must not make ~/.jai itself
def jai-dir []: nothing -> path { xdg data jai }

# The plain names on PATH: `jai` as the compiler's docs and jails call it (the beta ships only jai-linux).
def bins-link [dir: path]: nothing -> nothing {
    ^ln -sfn jai-linux ($dir | path join bin jai)
    ^ln -sfn ($dir | path join jails bin jails) ($dir | path join bin jails)
}

export def jai-install [zip: string]: nothing -> nothing {
    let dir = jai-dir
    nas-vendor-set-aside $dir
    rm --recursive --force $dir
    mkdir $dir
    ^unzip -q $zip -d $dir
    ls --all ($dir | path join jai) | each { mv $in.name $dir } | ignore
    rm ($dir | path join jai)
    ^$DOT internal fetch git $JAILS_URL $JAILS_COMMIT ($dir | path join jails)
    do { cd ($dir | path join jails); ^($dir | path join bin jai-linux) build.jai }
    bins-link $dir
    $"($zip | path basename)\n" | save --force ($dir | path join $NAS_VENDOR_STAMP)
}

export def jai-bins-link []: nothing -> nothing { bins-link (jai-dir) }

export def link [cfg: record] {
    if not (owner-unlocked) {
        if (profile-has secrets) { log-warn "jai: secrets locked" }
        return []
    }
    let dir = jai-dir
    let stamp = $dir | path join $NAS_VENDOR_STAMP
    let installed = if ($dir | path join bin jai-linux | path exists) { file-trim $stamp } else { "" }
    let plan = nas-vendor-plan (nas-vendor-dir) $installed $ZIP_GLOB
    if $plan.note != null { log-note $"jai: ($plan.note)" }
    [
        (if $plan.newer { step jai-install $plan.zip --key $plan.name --creates $stamp --network })
        (if $installed != "" and not $plan.newer { step jai-bins-link --done=($dir | path join bin jai | path exists) })
    ]
}
