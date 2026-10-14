use module.nu *

# the profiles are planned from profiles.ini, which the first run's headless step creates
export const meta = {packages: {pacman: [firefox python-pywalfox]}, inputs: ["~/.config/mozilla/firefox/profiles.ini"]}

const HOME_DIR = ".config/mozilla/firefox"
const FIREFOX_DIR = "/usr/lib/firefox"
const POLICIES = "/etc/firefox/policies/policies.json"
const PYWALFOX_HOST = ".mozilla/native-messaging-hosts/pywalfox.json"
# the run is ended on purpose; profiles.ini is the real result
const HEADLESS_TIMEOUT = "20"
const SEARCH_OFF_HOMELAB = {
    Add: [{Name: DuckDuckGo, URLTemplate: "https://duckduckgo.com/?q={searchTerms}", Method: GET, Alias: ddg}]
    Default: DuckDuckGo
}

def profiles [ini: path]: nothing -> list<path> {
    open --raw $ini | lines | parse "Path={path}" | get path | each {|p| $ini | path dirname | path join $p } | where ($it | path exists)
}

export def link [cfg: record] {
    let root = $nu.home-dir | path join $HOME_DIR
    let ini = $root | path join profiles.ini
    # no profile until the first run; a headless one creates default-release, the next link styles it
    if not ($ini | path exists) {
        return [(step profile-create)]
    }
    let pywalfox = if (which pywalfox | is-empty) { [] } else {
        # the native host lets the theme verb's `pywalfox update` push the palette into the force-installed addon
        [(exec pywalfox-host [pywalfox install] --creates ($nu.home-dir | path join $PYWALFOX_HOST))]
    }
    # pywalfox looks in ~/.config/firefox
    [(file-link $root ($nu.home-dir | path join .config firefox))]
    | append (profiles $ini | each {|dir|
        [
            # a link: toggle-font rewrites the repo file
            (file-link userChrome.css ($dir | path join chrome userChrome.css))
            (file-render user.js ($dir | path join user.js) {HOME: $nu.home-dir})
        ]
    } | flatten)
    | append $pywalfox
}

export def profile-create [] {
    ^timeout $HEADLESS_TIMEOUT firefox --headless about:blank | complete | ignore
}

# pywalfox pushes the wal colors to the running firefox's extension
export def theme [cfg: record, wallpaper: string] {
    if (which pywalfox | is-empty) { return [] }
    exec pywalfox-update [pywalfox update]
}

# the new tab url is only settable from autoconfig in the install dir, which survives updates; mozilla.cfg reads each
# user's home at runtime. the enterprise policy reaches every profile of every user: hardening, and the homelab's
# searxng as the engine, unreachable elsewhere, where duckduckgo replaces it rather than google
export def system [cfg: record] {
    let policies = if (platform-has homelab) {
        file-copy policies.json $POLICIES
    } else {
        file-text $POLICIES $"(open policies.json | upsert policies.SearchEngines $SEARCH_OFF_HOMELAB | to json --indent 2)\n"
    }
    let autoconfig = if ($FIREFOX_DIR | path exists) {
        [
            (file-copy autoconfig.js ($FIREFOX_DIR | path join defaults pref autoconfig.js))
            (file-copy mozilla.cfg ($FIREFOX_DIR | path join mozilla.cfg))
        ]
    } else { [] }
    [$policies] | append $autoconfig
}
