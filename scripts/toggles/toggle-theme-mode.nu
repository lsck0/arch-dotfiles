#!/usr/bin/env -S nu --no-config-file
use lib.nu [status-record status-print notify state-file]
use ../lib/log.nu [log-err]
use ../../configs/core/wallust/wallpaper-list.nu [wallpaper-resolve]
use ../../configs/core/wallust/palette.nu [hex-to-rgb is-light]

const THEMES = path self ../../themes
const DOT = path self ../dot.nu
const WAL = ".cache/wal"
const LAST_FLIP = "theme-mode.nuon"
const MODES = [dark light]

def wal [...parts: string]: nothing -> path { $nu.home-dir | path join $WAL ...$parts }

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

def background []: nothing -> any { try { open (wal colors.json) | get special.background } }

def current-mode []: nothing -> string { background | if $in == null { "dark" } else { mode-of $in } }

def current-wallpaper []: nothing -> string { try { ^readlink -f (wal wallpaper) | str trim } catch { "" } }

def distance [a: string, b: string]: nothing -> float {
    $a | hex-to-rgb | zip ($b | hex-to-rgb) | each { ($in.0 - $in.1) ** 2 } | math sum
}

def current-theme [themes: table, wallpaper: string]: nothing -> record {
    let named = $themes | where wallpaper == ($wallpaper | path basename) | get --optional 0
    if $named != null { return $named }
    let bg = background
    if $bg == null { error make {msg: "no palette in ~/.cache/wal, run dot theme first"} }
    $themes | where mode == (mode-of $bg) | sort-by { distance $in.background $bg } | first
}

def target []: nothing -> record {
    let themes = themes
    let from = current-wallpaper
    let mode = $MODES | where $it != (current-mode) | first
    let last = try { open (state-file $LAST_FLIP) }
    if $last != null and $last.to == $from and ($last.from | path exists) {
        let theme = $themes | where wallpaper == ($last.from | path basename) | get name.0? | default ""
        return {mode: $mode, theme: $theme, wallpaper: $last.from, from: $from}
    }
    let current = current-theme $themes $from
    let partner = $themes | where name == $current.pair | get --optional 0
    if $partner == null { error make {msg: $"($current.name) pairs with ($current.pair), which is no theme"} }
    let wallpaper = wallpaper-resolve $partner.wallpaper
    if $wallpaper == null { error make {msg: $"($partner.name): wallpaper ($partner.wallpaper) not found, secrets locked?"} }
    {mode: $partner.mode, theme: $partner.name, wallpaper: $wallpaper, from: $from}
}

def flip []: nothing -> nothing {
    try {
        let to = target
        ^nu --no-config-file $DOT theme --sync $to.wallpaper
        if (current-wallpaper) != ($to.wallpaper | path expand) { error make {msg: "a newer switch replaced this one"} }
        {from: $to.from, to: ($to.wallpaper | path expand)} | to nuon | save --force (state-file $LAST_FLIP)
        notify "Theme" $"($to.mode | str capitalize)(if $to.theme != '' { $': ($to.theme)' })"
    } catch {|err|
        notify "Theme" $"Failed to switch: ($err.msg)" --critical
        with-env {LOG_TAG: ($env.PROCESS_PATH | path basename)} { log-err $err.msg }
        exit 1
    }
}

def "main get" [--json] {
    let mode = current-mode
    status-print (status-record Theme $mode --text ($mode | str capitalize) --states [dark light]) $json
}

# what toggle would switch to, without switching
def "main target" [] { target | to json --raw }

def "main set" [mode: string] {
    if $mode not-in $MODES { error make {msg: $"theme mode is one of ($MODES | str join ', ')"} }
    if $mode != (current-mode) { flip }
}

def "main light" [] { main set light }
def "main dark" [] { main set dark }
def "main toggle" [] { flip }
def main [] { main toggle }
