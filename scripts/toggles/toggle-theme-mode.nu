#!/usr/bin/env -S nu --no-config-file
use lib.nu [DOT status-record status-print notify notify-failed state-file state-check]
use ../lib/log.nu [log-err]
use ../../configs/core/wallust/scripts/wallpaper-list.nu [wallpaper-resolve]
use ../../configs/core/wallust/scripts/wallpaper.nu [wallpaper-get theme-get]
use ../../configs/core/wallust/scripts/palette.nu [hex-to-rgb is-light wal-colors-file palette-load]

const THEMES = path self ../../themes
const LAST_FLIP = "theme-mode.nuon"
const MODES = [dark light]

def mode-of [hex: string]: nothing -> string { if ($hex | hex-to-rgb | is-light) { "light" } else { "dark" } }

def themes []: nothing -> table {
    glob ($THEMES | path join "*.json") | each {|file|
        let spec = open $file
        {
            name: ($file | path parse | get stem)
            wallpaper: $spec.wallpaper
            pair: $spec.pair
            background: $spec.special.background
            mode: (mode-of $spec.special.background)
        }
    }
}

def palette []: nothing -> record {
    let palette = palette-load
    if $palette == null { error make {msg: $"no palette in (wal-colors-file), run dot theme first"} }
    $palette
}

def current-mode []: nothing -> string { if (palette).light == "1" { "light" } else { "dark" } }

def distance [a: string, b: string]: nothing -> float {
    $a | hex-to-rgb | zip ($b | hex-to-rgb) | each { ($in.0 - $in.1) ** 2 } | math sum
}

# The theme in effect, for a derived palette the theme of its mode with the nearest background.
def current-theme [themes: table, palette: string]: nothing -> record {
    let named = $themes | where name == $palette | get --optional 0
    if $named != null { return $named }
    let bg = (palette).bg
    $themes | where mode == (mode-of $bg) | sort-by { distance $in.background $bg } | first
}

def target []: nothing -> record {
    let themes = themes
    let from = wallpaper-get
    let mode = $MODES | where $it != (current-mode) | first
    let palette = theme-get
    let last = try { open (state-file $LAST_FLIP) }
    if $last != null and $last.to == $from and $last.palette? != null and ($last.from | path exists) {
        let theme = if $last.palette in $themes.name { $last.palette } else { "" }
        return {mode: $mode, theme: $theme, wallpaper: $last.from, from: $from, palette: $palette}
    }
    let current = current-theme $themes $palette
    let partner = $themes | where name == $current.pair | get --optional 0
    if $partner == null { error make {msg: $"($current.name) pairs with ($current.pair), which is no theme"} }
    let wallpaper = wallpaper-resolve $partner.wallpaper
    if $wallpaper == null { error make {msg: $"($partner.name): wallpaper ($partner.wallpaper) not found, secrets locked?"} }
    {mode: $partner.mode, theme: $partner.name, wallpaper: $wallpaper, from: $from, palette: $palette}
}

def flip []: nothing -> nothing {
    try {
        let to = target
        ^nu --no-config-file $DOT theme --sync (if $to.theme != "" { $to.theme } else { $to.wallpaper })
        if (wallpaper-get) != ($to.wallpaper | path expand) { error make {msg: "a newer switch replaced this one"} }
        {from: $to.from, palette: $to.palette, to: ($to.wallpaper | path expand)} | to nuon | save --force (state-file $LAST_FLIP)
        notify "Theme" $"($to.mode | str capitalize)(if $to.theme != '' { $': ($to.theme)' })"
    } catch {|err|
        notify-failed Theme $err.msg
        with-env {LOG_TAG: ($env.PROCESS_PATH | path basename)} { log-err $err.msg }
        exit 1
    }
}

def "main get" [--json] {
    let status = try {
        let mode = current-mode
        status-record Theme $mode --text ($mode | str capitalize) --states $MODES
    } catch { status-record Theme error }
    status-print $status $json
}

# what toggle would switch to, without switching
def "main target" [] { target | to json --raw }

def "main set" [mode: string] {
    state-check "theme mode" $mode $MODES
    if $mode != (try { current-mode }) { flip }
}

def "main light" [] { main set light }
def "main dark" [] { main set dark }
def "main toggle" [] { flip }
# Theme: get [--json] prints dark or light, set <mode> or the mode's own name switches to the paired theme, target
# prints what toggle would pick, a bare call toggles.
def main [] { main toggle }
