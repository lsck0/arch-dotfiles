use module.nu *

export const meta = {packages: {pacman: [libreoffice-fresh]}}

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

export def link [cfg: record] {
    let xcu = xdg config libreoffice 4 user registrymodifications.xcu
    let text = if ($xcu | path exists) { open --raw $xcu } else { "" }
    step xcu-update $xcu --done=($text !~ $OVERRIDE and $text =~ $TIPS_KEY and $text =~ $VERSION_KEY)
}

export def xcu-update [xcu: path] {
    if (process-running soffice.bin) {
        log-warn "libreoffice: running, registry update skipped"
        return
    }
    let lines = if ($xcu | path exists) { open --raw $xcu | lines } else { $XCU_HEAD ++ [$XCU_TAIL] }
    let kept = $lines | where $it !~ $OVERRIDE
    let version = package-version libreoffice-fresh | default "" | split row "." | first 2 | str join "."
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
