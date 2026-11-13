use module.nu *
use ../firefox/mod.nu [HEADLESS_TIMEOUT mozilla-profiles mozilla-chrome-font]

export const meta = {
    packages: {pacman: [thunderbird]}
    inputs: ["~/.config/thunderbird/profiles.ini"]
}

# thunderbird keeps its profiles under the XDG config dir (since 156)
def profiles-ini []: nothing -> path { xdg config thunderbird profiles.ini }

export def link [cfg: record] {
    if (which thunderbird | is-empty) { return [] }
    let ini = profiles-ini
    if not ($ini | path exists) { return [(step profile-create)] }
    let colors = xdg cache wal colors-thunderbird.css
    mozilla-profiles $ini | each {|dir|
        [
            (file-copy userChrome.css ($dir | path join chrome userChrome.css))
            (file-link $colors ($dir | path join chrome colors.css))
        ]
    }
}

export def profile-create [] {
    ^timeout $HEADLESS_TIMEOUT thunderbird --headless | complete | ignore
}

# user.js's ui.systemUsesDarkTheme tracks the palette: content under a light wallust theme is not told it is dark
export def theme [cfg: record, wallpaper: string] {
    if (which thunderbird | is-empty) { return [] }
    let font = mozilla-chrome-font
    let p = palette-load
    let dark = if $p != null and $p.light == "1" { 0 } else { 1 }
    mozilla-profiles (profiles-ini) | each {|dir|
        [
            (file-text ($dir | path join chrome dotfiles-font.css) $font --generated)
            (file-render user.js ($dir | path join user.js) {DARK: $dark} --generated)
        ]
    }
}
