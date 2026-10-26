use module.nu *

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

export def link [cfg: record] {
    if (which thunderbird | is-empty) { return [] }
    let root = profiles-root
    if $root == null { return [(step profile-create)] }
    let colors = xdg cache wal colors-thunderbird.css
    open --raw ($root | path join profiles.ini) | lines | parse "Path={path}" | get path
    | each {|p| $root | path join $p } | where ($it | path exists) | each {|dir|
        [
            (file-copy userChrome.css ($dir | path join chrome userChrome.css))
            (file-link $colors ($dir | path join chrome colors.css))
            (file-copy user.js ($dir | path join user.js))
        ]
    } | flatten
}

export def profile-create [] {
    ^timeout $HEADLESS_TIMEOUT thunderbird --headless | complete | ignore
}
