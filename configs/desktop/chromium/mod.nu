use module.nu *

export const meta = {packages: {pacman: [chromium browserpass browserpass-chromium]}}

const POLICY = "/etc/chromium/policies/managed/policy.json"
const CHROMIUM_LIB = "/usr/lib/chromium"
const SEARCH_OFF_HOMELAB = {name: DuckDuckGo, url: "https://duckduckgo.com/?q={searchTerms}"}

# Forces system_theme, older profiles keep classic; only while chromium is closed, it rewrites Preferences on exit.
def profile-style [dir: path]: nothing -> list<record> {
    let prefs = $dir | path join Default Preferences
    if not ($prefs | path exists) { return [] }
    [(json-merge $prefs [(json-set [extensions theme system_theme] 1)])]
}

export def link [cfg: record] {
    let config = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config)
    profile-style ($config | path join chromium)
    | append (file-text ($config | path join chromium-flags.conf) "--no-first-run\n")
    | append (desktop-override chromium.desktop { str replace --all --regex '(?m)^Exec=chromium' 'Exec=chromium --ozone-platform-hint=auto' })
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
