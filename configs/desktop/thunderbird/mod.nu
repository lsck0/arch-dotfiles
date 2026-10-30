use module.nu *
use ../../core/wallust/palette.nu [wal-load is-light]
use ../../core/wallust/font.nu [font-load]

export const meta = {
    packages: {pacman: [thunderbird]}
    inputs: ["~/.config/thunderbird/profiles.ini"]
}

const HEADLESS_TIMEOUT = "20"

# thunderbird keeps its profiles under the XDG config dir (since 156); none yet before its first start
def profiles-root []: nothing -> any {
    let root = xdg config thunderbird
    if ($root | path join profiles.ini | path exists) { $root }
}

def profile-dirs [root: path]: nothing -> list<path> {
    open --raw ($root | path join profiles.ini) | lines | parse "Path={path}" | get path
    | each {|p| $root | path join $p } | where ($it | path exists)
}

# ui.systemUsesDarkTheme tracks the palette: content under a light wallust theme is not told the system is dark.
def dark-pref []: nothing -> int {
    let slot = wal-load "thunderbird"
    if $slot == null { return 1 }
    if (do $slot background "#000000" | is-light) { 0 } else { 1 }
}

export def link [cfg: record] {
    if (which thunderbird | is-empty) { return [] }
    let root = profiles-root
    if $root == null { return [(step profile-create)] }
    let colors = xdg cache wal colors-thunderbird.css
    profile-dirs $root | each {|dir|
        [
            (file-copy userChrome.css ($dir | path join chrome userChrome.css))
            (file-link $colors ($dir | path join chrome colors.css))
        ]
    } | flatten
}

export def profile-create [] {
    ^timeout $HEADLESS_TIMEOUT thunderbird --headless | complete | ignore
}

# the chrome's font, imported by userChrome.css; thunderbird reads it at its next start
def chrome-font []: nothing -> string {
    let font = font-load
    $":root {\n    --rtk-chrome-font: \"($font.family)\", \"JetBrainsMono Nerd Font\", monospace, sans-serif;\n    --rtk-chrome-font-size: ($font.ui_size)pt;\n}\n"
}

# user.js follows the palette's light flag
export def theme [cfg: record, wallpaper: string] {
    if (which thunderbird | is-empty) { return [] }
    let root = profiles-root
    if $root == null { return [] }
    let dark = dark-pref
    profile-dirs $root | each {|dir|
        [
            (file-text ($dir | path join chrome dotfiles-font.css) (chrome-font) --generated)
            (file-render user.js ($dir | path join user.js) {DARK: ($dark | into string)} --generated)
        ]
    } | flatten
}
