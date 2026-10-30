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
    search_method: {
        type: string
        default: "GET"
        doc: "GET or POST for the startpage's search form; most engines, the homelab's searxng too, take GET; POST works only in qutebrowser"
        label: "Search method"
        scope: user
    }
}

const CONFIG_DIR = ".config/qutebrowser"
const LISTS = [adblock-cache.dat blocked-hosts]
const FETCH_QUIT_MS = "60000"
const FETCH_TIMEOUT = "90"
# the bar's palette knobs, so the startpage's hues match it
const BAR_THEME = path self ../quickshell/theme.json
const FALLBACK = {
    bg: "#0d1117" surface: "#161b22" fg: "#c9d1d9" muted: "#8b949e" accent: "#58a6ff" accent2: "#d2a8ff" urgent: "#ff7b72"
}
const CHROME_COLORS = "wal/qutebrowser-colors.json"
const CHROME_ALT_SHADE = 0.03
# a match or a muted label keeps some of its hue: a distinct mark beside the text, not body text
const MARK_RATIO = 3.0

export def detect [cfg: record]: nothing -> record {
    {search_url: (if (platform-has homelab) { $SEARCH_HOMELAB } else { $SEARCH_DEFAULT })}
}

def lists-ready []: nothing -> bool {
    let data = xdg data qutebrowser
    $LISTS | all {|f| ($data | path join $f | path exists) and (ls ($data | path join $f) | get 0.size | into int) > 0 }
}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    [
        (file-copy config.py ($dir | path join config.py))
        (file-text ($dir | path join search-url) $"($cfg.search_url)\n")
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

def bar-knobs []: nothing -> record {
    let defaults = {
        foregroundContrast: $FOREGROUND_RATIO accentMinSaturation: $ACCENT_SATURATION_MIN accentMinValue: $ACCENT_VALUE_MIN
        textContrast: $TEXT_RATIO
    }
    $defaults | merge (open $BAR_THEME | get --optional palette | default {})
}

def accent-from [slot: closure, knobs: record]: nothing -> list<float> {
    do $slot color4 $FALLBACK.accent | vivify $knobs.accentMinSaturation $knobs.accentMinValue
}

# the bar's accent2 pool (Commons/Palette.js conditionPalette): colors 2, 3, 5, 6 away from the urgent hue
def accent2-from [slot: closure, knobs: record, accent: list<float>, bg: list<float>]: nothing -> list<float> {
    let urgent = do $slot color1 $FALLBACK.urgent
    let pool = [color2 color3 color5 color6]
        | each {|name| do $slot $name $FALLBACK.accent2 | vivify $knobs.accentMinSaturation $knobs.accentMinValue }
        | where {|c| (hue-apart $urgent $c) >= $URGENT_APART_MIN_DEG }
    if ($pool | is-empty) { $FALLBACK.accent2 | hex-to-rgb } else { accent2-pick $pool $accent $bg $ACCENT2_RATIO }
}

# the bar's roles from the wal palette (Commons/Palette.js conditionPalette), every one used as text raised to its textContrast
def startpage-colors []: nothing -> record {
    let slot = wal-load "qutebrowser startpage"
    if $slot == null {
        return {
            BG: $FALLBACK.bg SURFACE: $FALLBACK.surface FG: $FALLBACK.fg MUTED: $FALLBACK.muted ACCENT: $FALLBACK.accent
            ACCENT2: $FALLBACK.accent2
        }
    }
    let knobs = bar-knobs
    let bg = do $slot background $FALLBACK.bg | condition-bg
    # text sits on the panel, a mix of surface and bg: readable on surface is readable on any mix of the two
    let surface = $bg | shade 0.06
    let accent = accent-from $slot $knobs
    let hex = {|c| $c | rgb-to-hex --prefix "#" }
    {
        BG: (do $hex $bg)
        SURFACE: (do $hex $surface)
        FG: (do $hex (do $slot foreground $FALLBACK.fg | readable-on $surface --ratio $knobs.foregroundContrast))
        MUTED: (do $hex (do $slot color8 $FALLBACK.muted | readable-on $surface --ratio $knobs.textContrast))
        ACCENT: (do $hex ($accent | readable-on $surface --ratio $knobs.textContrast))
        ACCENT2: (do $hex (accent2-from $slot $knobs $accent $bg | readable-on $surface --ratio $knobs.textContrast))
    }
}

# config.py's chrome roles, conditioned like the startpage; config.py falls back to the raw slots without it.
def chrome-colors []: nothing -> any {
    let slot = wal-load "qutebrowser chrome"
    if $slot == null { return null }
    let bg = do $slot background $FALLBACK.bg | condition-bg
    # alt rows and tabs are the lower-contrast surface: text readable on it is readable on bg too
    let alt = $bg | shade $CHROME_ALT_SHADE
    let fg = do $slot foreground $FALLBACK.fg | readable-on $alt
    let accent = accent-from $slot (bar-knobs)
    let selection = do $slot color8 $FALLBACK.muted | selection-pair $fg
    let hex = {|c| $c | rgb-to-hex --prefix "#" }
    {
        bg: (do $hex $bg)
        bg_alt: (do $hex $alt)
        fg: (do $hex $fg)
        muted: (do $hex (do $slot color8 $FALLBACK.muted | readable-on $alt --ratio $MARK_RATIO))
        accent: (do $hex ($accent | readable-on $alt))
        selection_bg: (do $hex $selection.0)
        selection_fg: (do $hex $selection.1)
        selection_match: (do $hex ($accent | readable-on $selection.0 --ratio $MARK_RATIO))
        hint_bg: (do $hex $accent)
        hint_fg: (do $hex ($bg | readable-on $accent))
        hint_match: (do $hex (do $slot color1 $FALLBACK.urgent | readable-on $accent --ratio $MARK_RATIO))
    }
}

export def theme [cfg: record, wallpaper: string] {
    let chrome = chrome-colors
    let chrome_file = if $chrome == null { [] } else { [(file-text (xdg cache $CHROME_COLORS) ($chrome | to json --indent 2) --generated)] }
    let dest = $nu.home-dir | path join $CONFIG_DIR startpage.html
    let font = font-load
    let startpage = file-render startpage.html $dest ({
        CACHE: (xdg cache)
        DATA: (xdg data)
        RADIUS: $RADIUS_PX
        FONT: $font.family
        FONT_SIZE: $font.ui_size
        SEARCH: ($cfg.search_url | to json)
        METHOD: $cfg.search_method
    } | merge (startpage-colors)) --generated
    # without a running instance the command would start one
    if not (process-running qutebrowser) { return ($chrome_file ++ [$startpage]) }
    $chrome_file ++ [$startpage (exec qutebrowser-config-source [qutebrowser :config-source])]
}
