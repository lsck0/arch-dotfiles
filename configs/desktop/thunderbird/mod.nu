use module.nu *

# the profiles are planned from profiles.ini, which the first run's headless step creates
export const meta = {
    packages: {pacman: [thunderbird]}
    inputs: ["~/.config/thunderbird/profiles.ini" "~/.config/mozilla/thunderbird/profiles.ini" "~/.thunderbird/profiles.ini"]
}

const HEADLESS_TIMEOUT = "20"

# a fresh home gets ~/.config/thunderbird (156 on), older homes keep ~/.thunderbird
def profiles-root []: nothing -> any {
    let config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config)
    [($config | path join thunderbird) ($nu.home-dir | path join .config mozilla thunderbird) ($nu.home-dir | path join .thunderbird)]
    | where ($it | path join profiles.ini | path exists) | get --optional 0
}

export def link [cfg: record] {
    if (which thunderbird | is-empty) { return [] }
    let root = profiles-root
    # no profile until the first run; a headless one creates it, the next link styles it
    if $root == null { return [(step profile-create)] }
    let colors = $nu.home-dir | path join .cache wal colors-thunderbird.css
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
