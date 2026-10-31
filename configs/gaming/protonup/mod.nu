use module.nu *

const PROTON_GE_VERSION = "GE-Proton11-7"
const PROTON_GE_SHA256 = "c5448b76a230384e2d7bc6beb5ccb97bafb7e2c3b6c527cb03a1a546bbcb00a0"
const OVERLAY_URL = "https://github.com/thaylorz/proton-ge-custom/releases/download/proton-layered-overlay-v1/Proton-LayeredOverlay.tar.gz"
const OVERLAY_SHA256 = "ba515bf1fa6e7f9634cb894640f21f0359dc7435c3a5ce458a37087ed6c3a4d7"
const OVERLAY_DIR = "Proton-LayeredOverlay"

def steam-data []: nothing -> path {
    xdg data Steam
}

# Not ~/.steam/root, a link steam.sh makes on first launch: a real dir there blocks it, so the tools go to the data dir.
export def link [cfg: record] {
    let compat = steam-data | path join compatibilitytools.d
    let ge = $"($PROTON_GE_VERSION)-x86_64"
    let ge_url = $"https://github.com/GloriousEggroll/proton-ge-custom/releases/download/($PROTON_GE_VERSION)/($ge).tar.gz"
    [
        (fetch-file $ge_url $PROTON_GE_SHA256 ($compat | path join $ge) --extract $ge)
        (fetch-file $OVERLAY_URL $OVERLAY_SHA256 ($compat | path join $OVERLAY_DIR) --extract $OVERLAY_DIR)
    ]
}
