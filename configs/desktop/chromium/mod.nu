use module.nu *

export const meta = {packages: {pacman: [chromium browserpass browserpass-chromium]}}

const POLICY = "/etc/chromium/policies/managed/policy.json"
const CHROMIUM_LIB = "/usr/lib/chromium"
const SEARCH_OFF_HOMELAB = {name: DuckDuckGo, url: "https://duckduckgo.com/?q={searchTerms}"}
# Chromium Private is the Default profile, Chromium Streaming keeps stream logins and history off it; Chromium Work
# (secrets/capgemini) has a data dir of its own. Each name shows in the launcher and chromium's profile menu.
const PROFILES = {Default: Private, Streaming: Streaming}

# Forces system_theme and the profile's name; chromium creates Preferences on a profile's first start and rewrites it on
# exit, so an edit made while it runs re-applies on the next apply.
def profile-style [dir: path]: nothing -> list<record> {
    $PROFILES | items {|profile, name|
        let prefs = $dir | path join $profile Preferences
        if not ($prefs | path exists) { return [] }
        [(json-merge $prefs [(json-set [extensions theme system_theme] 1) (json-set [profile name] $name)])]
    } | flatten
}

export def link [cfg: record] {
    let config = (xdg config)
    profile-style ($config | path join chromium)
    | append (file-text ($config | path join chromium-flags.conf) "--no-first-run\n--ozone-platform-hint=auto\n")
    | append (files-into (xdg data applications) chromium-streaming.desktop)
    | append (desktop-override chromium.desktop { desktop-set {Name: "Chromium Private"} })
}

export def system [cfg: record] {
    let policy = if (platform-has homelab) {
        file-copy policy.json $POLICY
    } else {
        let text = open policy.json
            | upsert DefaultSearchProviderName $SEARCH_OFF_HOMELAB.name | upsert DefaultSearchProviderSearchURL $SEARCH_OFF_HOMELAB.url
            | to json --indent 2
        file-text $POLICY $"($text)\n"
    }
    [$policy] | append (if ($CHROMIUM_LIB | path exists) { [(file-copy initial_preferences ($CHROMIUM_LIB | path join initial_preferences))] } else { [] })
}
