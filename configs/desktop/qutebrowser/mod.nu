use module.nu *
use ../../core/wallust/palette.nu *
use ../../core/wallust/font.nu [font-load]

export const meta = {deps: [core/wallust], packages: {pacman: [qutebrowser python-adblock]}}

const SEARCH_DEFAULT = "https://duckduckgo.com/?q={}"
const SEARCH_HOMELAB = "https://search.lsck0.dev/search?q={}"

export const options = {
    search_url: {
        type: string
        default: $SEARCH_DEFAULT
        doc: "The default search engine, {} is the query; the homelab's searxng is reachable only on a homelab machine"
        label: "Search engine URL"
        scope: user
    }
}

const CONFIG_DIR = ".config/qutebrowser"
const LISTS = [adblock-cache.dat blocked-hosts]
const FETCH_QUIT_MS = "60000"
const FETCH_TIMEOUT = "90"

export def detect [cfg: record]: nothing -> record {
    {search_url: (if (platform-has homelab) { $SEARCH_HOMELAB } else { $SEARCH_DEFAULT })}
}

def lists-ready []: nothing -> bool {
    let data = xdg data qutebrowser
    $LISTS | all {|f| ($data | path join $f | path exists) and (ls ($data | path join $f) | get 0.size | into int) > 0 }
}

export def link [cfg: record] {
    let search = if $cfg.search_url == $SEARCH_DEFAULT { (detect $cfg).search_url } else { $cfg.search_url }
    let dir = $nu.home-dir | path join $CONFIG_DIR
    [
        (file-copy config.py ($dir | path join config.py))
        (file-text ($dir | path join search-url) $"($search)\n")
    ] | append (if (lists-ready) { [] } else { [(step lists-fetch)] })
}

# Fetches the adblock lists in a windowless instance, never beside a running one: the quit would reach it over ipc.
export def lists-fetch [] {
    if (process-running qutebrowser) { return }
    with-env {QT_QPA_PLATFORM: offscreen} {
        ^timeout $FETCH_TIMEOUT qutebrowser --nowindow ":adblock-update" $":later ($FETCH_QUIT_MS) quit" | complete | ignore
    }
    if not (lists-ready) { log-warn "qutebrowser: block lists not fetched, dot apply --user --force desktop/qutebrowser retries" }
}

# the shell's roles from the wal palette, the same derivations caido and the bar use
def startpage-colors []: nothing -> record {
    let slot = wal-load "qutebrowser startpage"
    if $slot == null { return {BG: "#0d1117" SURFACE: "#161b22" FG: "#c9d1d9" MUTED: "#8b949e" ACCENT: "#58a6ff" ACCENT2: "#d2a8ff"} }
    let bg = do $slot background "#0d1117" | condition-bg
    let hex = {|c| $c | rgb-to-hex --prefix "#" }
    {
        BG: (do $hex $bg)
        SURFACE: (do $hex ($bg | shade 0.06))
        FG: (do $hex (do $slot foreground "#c9d1d9" | readable-on $bg))
        MUTED: (do $hex (do $slot color8 "#8b949e" | readable-on $bg --ratio 3.0))
        ACCENT: (do $hex (do $slot color4 "#58a6ff" | vivify 0.55 0.62 | readable-on $bg --ratio 3.0))
        ACCENT2: (do $hex (do $slot color5 "#d2a8ff" | vivify 0.55 0.62 | readable-on $bg --ratio 3.0))
    }
}

export def theme [cfg: record, wallpaper: string] {
    let dest = $nu.home-dir | path join $CONFIG_DIR startpage.html
    let search = if $cfg.search_url == $SEARCH_DEFAULT { (detect $cfg).search_url } else { $cfg.search_url }
    let startpage = file-render startpage.html $dest ({
        HOME: $nu.home-dir
        DATA: ((xdg data))
        RADIUS: $RADIUS_PX
        FONT: (font-load).family
        SEARCH: $search
    } | merge (startpage-colors)) | file-text $dest $in.content --generated
    # without a running instance the command would start one
    if not (process-running qutebrowser) { return [$startpage] }
    [$startpage (exec qutebrowser-config-source [qutebrowser :config-source])]
}
