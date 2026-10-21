use module.nu *

export const meta = {packages: {pacman: [protonup-git]}}

const PROTON_GE_VERSION = "GE-Proton11-7"
const PROTON_GE_SHA256 = "c5448b76a230384e2d7bc6beb5ccb97bafb7e2c3b6c527cb03a1a546bbcb00a0"
const OVERLAY_URL = "https://github.com/thaylorz/proton-ge-custom/releases/download/proton-layered-overlay-v1/Proton-LayeredOverlay.tar.gz"
const OVERLAY_SHA256 = "ba515bf1fa6e7f9634cb894640f21f0359dc7435c3a5ce458a37087ed6c3a4d7"
const OVERLAY_DIR = "Proton-LayeredOverlay"

def steam-data []: nothing -> path {
    $nu.home-dir | path join .local share Steam
}

# Not ~/.steam/root, a link steam.sh makes on first launch: a real dir there blocks it, so the tools go to the data dir.
export def link [cfg: record] {
    let compat = steam-data | path join compatibilitytools.d
    let ge = $"($PROTON_GE_VERSION)-x86_64"
    let ge_url = $"https://github.com/GloriousEggroll/proton-ge-custom/releases/download/($PROTON_GE_VERSION)/($ge).tar.gz"
    let stale = $nu.home-dir | path join .steam root
    [
        (if ($stale | path type) == dir { step root-repair } else { [] })
        (fetch-file $ge_url $PROTON_GE_SHA256 ($compat | path join $ge) --extract $ge)
        (fetch-file $OVERLAY_URL $OVERLAY_SHA256 ($compat | path join $OVERLAY_DIR) --extract $OVERLAY_DIR)
    ]
}

export def root-repair []: nothing -> nothing {
    let stale = $nu.home-dir | path join .steam root
    let compat = steam-data | path join compatibilitytools.d
    mkdir $compat
    for tool in (glob ($stale | path join compatibilitytools.d *)) {
        let dest = $compat | path join ($tool | path basename)
        if not ($dest | path exists) { mv $tool $dest }
    }
    rm --recursive --force ($stale | path join compatibilitytools.d)
    if ($stale | path join Steam | path type) == symlink { rm ($stale | path join Steam) }
    ^rmdir $stale
    ^ln -s (steam-data) $stale
}
