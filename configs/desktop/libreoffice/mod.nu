use module.nu *

export const meta = {packages: {pacman: [libreoffice-fresh]}}

const XCU = ".config/libreoffice/4/user/registrymodifications.xcu"
# a stored appearance or libreoffice theme paints its dialogs in its own light palette instead of the gtk (oomox) one
const OVERRIDE = 'oor:path="/org.openoffice.Office.Common/Appearance"><prop oor:name="(ApplicationAppearance|LibreOfficeTheme)"'

export def link [cfg: record] {
    let xcu = $nu.home-dir | path join $XCU
    if not ($xcu | path exists) or (open --raw $xcu) !~ $OVERRIDE { return [] }
    step appearance-reset $xcu
}

export def appearance-reset [xcu: path] {
    # libreoffice rewrites the file on exit, an edit under a running instance would be lost
    if (ps | where name == soffice.bin | is-not-empty) {
        log-warn "libreoffice: running, appearance reset skipped"
        return
    }
    open --raw $xcu | lines | where $it !~ $OVERRIDE | str join "\n" | $"($in)\n" | save --force $xcu
}
