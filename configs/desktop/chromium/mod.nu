use module.nu *
use ../firefox/mod.nu [SEARCH_URL_PATTERN search-name]

export const meta = {packages: {pacman: [chromium browserpass browserpass-chromium]}}

export const options = {
    # machine: the policy is /etc's, one for every login
    search_url: {
        type: string?
        default: null
        doc: "Default search engine, {searchTerms} is the query; unset, the homelab's searxng on a homelab machine, else duckduckgo"
        label: "Search engine URL"
        pattern: $SEARCH_URL_PATTERN
    }
}

const POLICY = "/etc/chromium/policies/managed/policy.json"
const SEARCH_OFF_HOMELAB = {name: DuckDuckGo, url: "https://duckduckgo.com/?q={searchTerms}"}
# Chromium Private is the Default profile, Chromium Streaming keeps stream logins and history off it; the owner's work
# profile (a secrets module) has a data dir of its own. Each name shows in the launcher and chromium's profile menu.
const PROFILES = {Default: Private, Streaming: Streaming}

# Forces system_theme and the profile's name; chromium creates Preferences on a profile's first start and rewrites it on
# exit, so an edit made while it runs re-applies on the next apply.
def profile-style [dir: path]: nothing -> list<any> {
    $PROFILES | items {|profile, name|
        let prefs = $dir | path join $profile Preferences
        if ($prefs | path exists) { json-merge $prefs [(json-set [extensions theme system_theme] 1) (json-set [profile name] $name)] }
    }
}

export def link [cfg: record] {
    [
        (profile-style (xdg config chromium))
        # a new profile takes its GTK theme from profile-style on the next apply; chromium 158 reads none of the
        # distribution keys that would skip the first-run ui instead
        (file-text (xdg config chromium-flags.conf) "--no-first-run\n--ozone-platform-hint=auto\n")
        (files-into (xdg data applications) config/chromium-streaming.desktop)
        (desktop-override chromium.desktop { desktop-set {Name: "Chromium Private"} })
    ]
}

export def system [cfg: record] {
    let search = if $cfg.search_url != null {
        {name: (search-name $cfg.search_url), url: $cfg.search_url}
    } else if not (platform-has homelab) { $SEARCH_OFF_HOMELAB }
    if $search == null { return [(file-copy config/policy.json $POLICY)] }
    let text = open config/policy.json
        | upsert DefaultSearchProviderName $search.name | upsert DefaultSearchProviderSearchURL $search.url
        | to json --indent 2
    [(file-text $POLICY $"($text)\n")]
}
