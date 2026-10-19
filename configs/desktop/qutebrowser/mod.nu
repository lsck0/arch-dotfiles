use module.nu *
use ../../core/wallust/palette.nu [RADIUS_PX]

# config.py reads the style.json core/wallust writes, also in the first link's lists-fetch
export const meta = {deps: [core/wallust], packages: {pacman: [qutebrowser python-adblock]}}

const SEARCH_DEFAULT = "https://duckduckgo.com/?q={}"
const SEARCH_HOMELAB = "https://search.lsck0.dev/search?q={}"

export const options = {
    search_url: {
        type: string
        default: $SEARCH_DEFAULT
        doc: "The default search engine, {} is the query; the homelab's searxng is reachable only on a homelab machine"
        label: "Search engine URL"
    }
}

const CONFIG_DIR = ".config/qutebrowser"
const LISTS = [adblock-cache.dat blocked-hosts]
# :adblock-update downloads in the background, the windowless instance quits once both lists had time to land
const FETCH_QUIT_MS = "60000"
const FETCH_TIMEOUT = "90"

export def detect [cfg: record]: nothing -> record {
    {search_url: (if (platform-has homelab) { $SEARCH_HOMELAB } else { $SEARCH_DEFAULT })}
}

def lists-ready []: nothing -> bool {
    let data = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join qutebrowser
    $LISTS | all {|f| ($data | path join $f | path exists) and (ls ($data | path join $f) | get 0.size | into int) > 0 }
}

export def link [cfg: record] {
    # until the engine merges detect itself: a value still at its default takes the detected one
    let search = if $cfg.search_url == $SEARCH_DEFAULT { (detect $cfg).search_url } else { $cfg.search_url }
    let dir = $nu.home-dir | path join $CONFIG_DIR
    [
        # a link: toggle-font rewrites the repo file
        (file-link config.py ($dir | path join config.py))
        (file-text ($dir | path join search-url) $"($search)\n")
        # a per-user copy: the page needs absolute paths into this home; toggle-font edits this copy and the repo's
        (file-render startpage.html ($dir | path join startpage.html) {HOME: $nu.home-dir, DOTFILES: $env.DOTFILES, RADIUS: $RADIUS_PX})
    ] | append (if (lists-ready) { [] } else { [(step lists-fetch)] })
}

def qutebrowser-running []: nothing -> bool { (^pgrep -x qutebrowser | complete).exit_code == 0 }

# never while one runs: the commands would reach it over ipc, the quit included
export def lists-fetch [] {
    if (qutebrowser-running) { return }
    with-env {QT_QPA_PLATFORM: offscreen} {
        ^timeout $FETCH_TIMEOUT qutebrowser --nowindow ":adblock-update" $":later ($FETCH_QUIT_MS) quit" | complete | ignore
    }
    if not (lists-ready) { log-warn "qutebrowser: block lists not fetched, dot apply --user --force desktop/qutebrowser retries" }
}

# config.py reads the palette when sourced; without a running instance the command would start one
export def theme [cfg: record, wallpaper: string] {
    if not (qutebrowser-running) { return [] }
    exec qutebrowser-config-source [qutebrowser :config-source]
}
