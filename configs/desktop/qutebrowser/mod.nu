use module.nu *
use ../../core/wallust/scripts/palette.nu *
use ../../core/wallust/scripts/font.nu [font-load]
use ../../../platforms/homelab.nu [HOMELAB]

export const meta = {deps: [core/wallust], packages: {pacman: [qutebrowser python-adblock]}}

const SEARCH_DEFAULT = "https://duckduckgo.com/?q={}"
const SEARCH_HOMELAB = $"https://search.($HOMELAB.domain)/search?q={}"

export const options = {
    # null so detect fills it: a detected value only lands on an option without a default
    search_url: {
        type: string?
        default: null
        doc: ("The default search engine, {} is the query; unset, the homelab's searxng on a homelab machine, else "
            + "duckduckgo")
        label: "Search engine URL"
        scope: user
    }
    search_method: {
        type: string
        default: "GET"
        choices: [GET POST]
        doc: "The startpage's search form method; most engines, the homelab's searxng too, take GET; POST works only in qutebrowser"
        label: "Search method"
        scope: user
    }
    tabs_position: {
        type: string
        default: "top"
        choices: [top bottom left right]
        doc: "Where the tab bar sits"
        label: "Tab bar position"
        scope: user
    }
    tabs_show: {
        type: string
        default: "multiple"
        choices: [always never multiple switching]
        doc: "When the tab bar shows: always, never, with more than one tab, or while switching"
        label: "Tab bar shown"
        scope: user
    }
    statusbar_show: {
        type: string
        default: "in-mode"
        choices: [always never in-mode]
        doc: "When the status bar shows; in-mode, only outside normal mode"
        label: "Status bar shown"
        scope: user
    }
    startpage_links: {
        type: list<record>
        default: []
        doc: "Start page links, also firefox's home: {group, sub?, name, url}; for a profile without secrets, whose weblinks module writes them"
        label: "Start page links"
        scope: user
    }
    # qutebrowser never updates them itself
    lists_max_age_days: {
        type: int
        default: 7
        min: 1
        max: 90
        doc: "Age at which the adblock lists are fetched again on the next apply"
        label: "Block list refresh (days)"
        scope: user
    }
}

const CONFIG_DIR = ".config/qutebrowser"
const LISTS = [adblock-cache.dat blocked-hosts]
const FETCH_QUIT_MS = "60000"
const FETCH_TIMEOUT = "90"
# the bar's palette knobs, so the startpage's hues match it
const BAR_THEME = path self ../quickshell/config/theme.json
# the startpage before the first theme; accent2 also when every pool colour sits on the urgent hue
const FALLBACK = {
    bg: "#0d1117" surface: "#161b22" fg: "#c9d1d9" muted: "#8b949e" accent: "#58a6ff" accent2: "#d2a8ff"
}
const CHROME_COLORS = "wal/qutebrowser-colors.json"
const CHROME_ALT_SHADE = 0.03
const STARTPAGE_SURFACE_SHADE = 0.06

export def detect [cfg: record]: nothing -> record {
    {search_url: (if (platform-has homelab) { $SEARCH_HOMELAB } else { $SEARCH_DEFAULT })}
}

def lists-ready [max_age_days: int]: nothing -> bool {
    let data = xdg data qutebrowser
    $LISTS | each {|f| $data | path join $f } | all {|f|
        ($f | path exists) and (ls $f | first | ($in.size | into int) > 0 and (date now) - $in.modified < ($max_age_days * 1day))
    }
}

export def link [cfg: record] {
    let dir = $nu.home-dir | path join $CONFIG_DIR
    [
        (file-render config/config.py ($dir | path join config.py) {
            TABS_POSITION: $cfg.tabs_position, TABS_SHOW: $cfg.tabs_show, STATUSBAR_SHOW: $cfg.statusbar_show
            # a JSON string's body is a valid Python string body: a quote or backslash in the url stays escaped
            SEARCH: ($cfg.search_url | default $SEARCH_DEFAULT | to json | str substring 1..-2)
        })
        # startpage.html loads weblinks/links.js, the owner's secrets module's otherwise
        (if ($cfg.startpage_links | is-not-empty) and not (profile-has secrets) {
            file-text (xdg data weblinks links.js) $"const weblinks = ($cfg.startpage_links | to json --raw);\n"
        })
        (step lists-fetch ($cfg.lists_max_age_days | into string) --network --done=(lists-ready $cfg.lists_max_age_days))
    ]
}

# Fetches the adblock lists in a windowless instance, never beside a running one: the quit would reach it over ipc.
export def lists-fetch [max_age_days: string] {
    if (process-running qutebrowser) { return }
    with-env {QT_QPA_PLATFORM: offscreen} {
        ^timeout $FETCH_TIMEOUT qutebrowser --nowindow ":adblock-update" $":later ($FETCH_QUIT_MS) quit" | complete | ignore
    }
    if not (lists-ready ($max_age_days | into int)) { log-warn "qutebrowser: block lists not fetched, dot apply --user --force desktop/qutebrowser retries" }
}

def bar-knobs []: nothing -> record {
    let defaults = {
        foregroundContrast: $FOREGROUND_RATIO accentMinSaturation: $ACCENT_SATURATION_MIN accentMinValue: $ACCENT_VALUE_MIN
        textContrast: $TEXT_RATIO
    }
    $defaults | merge (open $BAR_THEME | get --optional palette | default {})
}

def accent-from [p: record, knobs: record]: nothing -> list<float> {
    $p.c4 | vivify $knobs.accentMinSaturation $knobs.accentMinValue
}

# the bar's accent2 pool (Commons/Palette.js conditionPalette): colors 2, 3, 5, 6 away from the urgent hue
def accent2-from [p: record, knobs: record, accent: list<float>, bg: list<float>]: nothing -> list<float> {
    let pool = [$p.c2 $p.c3 $p.c5 $p.c6]
        | each { vivify $knobs.accentMinSaturation $knobs.accentMinValue }
        | where {|c| (hue-apart $p.c1 $c) >= $URGENT_APART_MIN_DEG }
    if ($pool | is-empty) { $FALLBACK.accent2 | hex-to-rgb } else { accent2-pick $pool $accent $bg $ACCENT2_RATIO }
}

# the bar's roles from the wal palette (Commons/Palette.js conditionPalette), every one used as text raised to its textContrast
def startpage-colors []: nothing -> record {
    let p = palette-rgb "qutebrowser startpage"
    if $p == null { return ($FALLBACK | rename --block { str uppercase }) }
    let knobs = bar-knobs
    let bg = $p.bg | condition-bg
    # text sits on the panel, a mix of surface and bg: readable on surface is readable on any mix of the two
    let surface = $bg | shade $STARTPAGE_SURFACE_SHADE
    let accent = accent-from $p $knobs
    let hex = {|c| $c | rgb-to-hex --prefix "#" }
    {
        BG: (do $hex $bg)
        SURFACE: (do $hex $surface)
        FG: (do $hex ($p.fg | readable-on $surface --ratio $knobs.foregroundContrast))
        MUTED: (do $hex ($p.c8 | readable-on $surface --ratio $knobs.textContrast))
        ACCENT: (do $hex ($accent | readable-on $surface --ratio $knobs.textContrast))
        ACCENT2: (do $hex (accent2-from $p $knobs $accent $bg | readable-on $surface --ratio $knobs.textContrast))
    }
}

# the shell's glass on the palette's background: dark and light themes take different fills
def glass-percent []: nothing -> int {
    let p = palette-rgb "qutebrowser startpage"
    let light = $p != null and ($p.bg | condition-bg | is-light)
    (if $light { $OPACITY_SHELL_LIGHT } else { $OPACITY_SHELL }) * 100 | math round
}

# config.py's chrome roles, conditioned like the startpage; config.py falls back to the raw slots without it.
def chrome-colors []: nothing -> any {
    let p = palette-rgb "qutebrowser chrome"
    if $p == null { return null }
    let bg = $p.bg | condition-bg
    # alt rows and tabs are the lower-contrast surface: text readable on it is readable on bg too
    let alt = $bg | shade $CHROME_ALT_SHADE
    let fg = $p.fg | readable-on $alt
    let accent = accent-from $p (bar-knobs)
    let selection = $p.c8 | selection-pair $fg
    let hex = {|c| $c | rgb-to-hex --prefix "#" }
    {
        bg: (do $hex $bg)
        bg_alt: (do $hex $alt)
        fg: (do $hex $fg)
        muted: (do $hex ($p.c8 | readable-on $alt --ratio $ACCENT2_RATIO))
        accent: (do $hex ($accent | readable-on $alt))
        selection_bg: (do $hex $selection.0)
        selection_fg: (do $hex $selection.1)
        selection_match: (do $hex ($accent | readable-on $selection.0 --ratio $ACCENT2_RATIO))
        hint_bg: (do $hex $accent)
        hint_fg: (do $hex ($bg | readable-on $accent))
        hint_match: (do $hex ($p.c1 | readable-on $accent --ratio $ACCENT2_RATIO))
    }
}

# Without a running instance the command would start one.
export def config-source []: nothing -> nothing {
    if not (process-running qutebrowser) { return }
    ^qutebrowser :config-source
}

export def theme [cfg: record, wallpaper: string] {
    # config.py reads both, and the chrome roles change with every palette, so the reload hangs off them
    let reload = then-step config-source
    let chrome = chrome-colors
    let dest = $nu.home-dir | path join $CONFIG_DIR startpage.html
    let font = font-load
    let startpage = file-render config/startpage.html $dest ({
        CACHE: (xdg cache)
        DATA: (xdg data)
        RADIUS: $RADIUS_PX
        EDGE: ($EDGE_ALPHA * 100 | math round)
        GLASS: (glass-percent)
        FONT: $font.family
        FONT_SIZE: $font.ui_size
        SEARCH: ($cfg.search_url | default $SEARCH_DEFAULT | to json)
        METHOD: $cfg.search_method
    } | merge (startpage-colors)) --generated --then $reload
    [
        (if $chrome != null { file-text (xdg cache $CHROME_COLORS) ($chrome | to json --indent 2) --generated --then $reload })
        $startpage
    ]
}
