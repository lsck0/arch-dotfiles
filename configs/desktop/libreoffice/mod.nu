use module.nu *

export const meta = {packages: {pacman: [libreoffice-fresh]}}

const XCU = ".config/libreoffice/4/user/registrymodifications.xcu"
# a stored appearance or theme paints the dialogs in its own light palette instead of the gtk one
const OVERRIDE = 'oor:path="/org.openoffice.Office.Common/Appearance"><prop oor:name="(ApplicationAppearance|LibreOfficeTheme)"'
const TIPS_KEY = 'oor:name="ShowTipOfTheDay"'
const TIPS = '<item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="ShowTipOfTheDay" oor:op="fuse"><value>false</value></prop></item>'
const VERSION_KEY = 'oor:name="ooSetupLastVersion"'
const XCU_HEAD = [
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
]
const XCU_TAIL = "</oor:items>"

def version-installed []: nothing -> string {
    let installed = ^pacman -Q libreoffice-fresh | complete
    if $installed.exit_code != 0 { return "" }
    $installed.stdout | str trim | split row " " | last | split row "." | first 2 | str join "."
}

export def link [cfg: record] {
    let xcu = $nu.home-dir | path join $XCU
    let text = if ($xcu | path exists) { open --raw $xcu } else { "" }
    if $text !~ $OVERRIDE and $text =~ $TIPS_KEY and $text =~ $VERSION_KEY { return [] }
    step xcu-update $xcu
}

export def xcu-update [xcu: path] {
    if (ps | where name == soffice.bin | is-not-empty) {
        log-warn "libreoffice: running, registry update skipped"
        return
    }
    let lines = if ($xcu | path exists) { open --raw $xcu | lines } else { $XCU_HEAD ++ [$XCU_TAIL] }
    let kept = $lines | where $it !~ $OVERRIDE
    let version = version-installed
    let seeds = [
        (if ($kept | any { $in =~ $TIPS_KEY }) { null } else { $TIPS })
        (if ($kept | any { $in =~ $VERSION_KEY }) or ($version | is-empty) { null } else {
            $'<item oor:path="/org.openoffice.Setup/Product"><prop ($VERSION_KEY) oor:op="fuse"><value>($version)</value></prop></item>'
        })
    ] | compact
    let seeded = $kept | each {|line| if $line == $XCU_TAIL { $seeds | append $line } else { [$line] } } | flatten
    mkdir ($xcu | path dirname)
    $seeded | str join "\n" | $"($in)\n" | save --force $xcu
}
