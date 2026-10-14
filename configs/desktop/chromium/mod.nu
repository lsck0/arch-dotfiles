use module.nu *

export const meta = {packages: {pacman: [chromium browserpass browserpass-chromium]}}

const POLICY = "/etc/chromium/policies/managed/policy.json"
const CHROMIUM_LIB = "/usr/lib/chromium"
const SEARCH_OFF_HOMELAB = {name: DuckDuckGo, url: "https://duckduckgo.com/?q={searchTerms}"}

# older profiles keep classic, so system_theme is forced; chromium rewrites Preferences on exit, so only while closed
def profile-style [dir: path]: nothing -> list<record> {
    let prefs = $dir | path join Default Preferences
    if not ($prefs | path exists) { return [] }
    [(json-merge $prefs [(json-set [extensions theme system_theme] 1)])]
}

export def link [cfg: record] {
    let work = if (profile-has work) {
        profile-style ($env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join capgemini chromium)
    } else { [] }
    profile-style ($env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join .config) | path join chromium)
    | append $work
    # native wayland, so the pipewire screencast portal works
    | append (desktop-override chromium.desktop { str replace --all --regex '(?m)^Exec=chromium' 'Exec=chromium --ozone-platform-hint=auto' })
}

# the homelab's searxng, unreachable elsewhere, where duckduckgo replaces it rather than google
export def system [cfg: record] {
    let policy = if (platform-has homelab) {
        file-copy policy.json $POLICY
    } else {
        let text = open policy.json
            | upsert DefaultSearchProviderName $SEARCH_OFF_HOMELAB.name | upsert DefaultSearchProviderSearchURL $SEARCH_OFF_HOMELAB.url
            | to json --indent 2
        file-text $POLICY $"($text)\n"
    }
    # chromium picks the gtk theme by itself only on gnome-likes; next to the real binary, a file the package does not own
    [$policy] | append (if ($CHROMIUM_LIB | path exists) { [(file-copy initial_preferences ($CHROMIUM_LIB | path join initial_preferences))] } else { [] })
}
