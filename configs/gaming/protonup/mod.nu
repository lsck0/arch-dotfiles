use module.nu *

const PROTON_GE_VERSION = "GE-Proton11-14"
const PROTON_GE_SHA256 = "26bcea3324b68dee68bf6b9b005f4425cdb9c29872e126d790df5abfebe332a8" # released 2026-11-23
const OVERLAY_URL = "https://github.com/thaylorz/proton-ge-custom/releases/download/proton-layered-overlay-v1/Proton-LayeredOverlay.tar.gz"
const OVERLAY_SHA256 = "ba515bf1fa6e7f9634cb894640f21f0359dc7435c3a5ce458a37087ed6c3a4d7" # released 2026-06-09
const OVERLAY_DIR = "Proton-LayeredOverlay"

# Not ~/.steam/root, a link steam.sh makes on first launch: a real dir there blocks it, so the tools go to the data dir.
export def link [cfg: record] {
    let compat = xdg data Steam compatibilitytools.d
    let ge = $"($PROTON_GE_VERSION)-x86_64"
    let ge_url = $"https://github.com/GloriousEggroll/proton-ge-custom/releases/download/($PROTON_GE_VERSION)/($ge).tar.gz"
    [
        (fetch-file $ge_url $PROTON_GE_SHA256 ($compat | path join $ge) --extract $ge)
        (fetch-file $OVERLAY_URL $OVERLAY_SHA256 ($compat | path join $OVERLAY_DIR) --extract $OVERLAY_DIR)
    ]
}
