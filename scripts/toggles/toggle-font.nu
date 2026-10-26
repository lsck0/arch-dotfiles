#!/usr/bin/env -S nu --no-config-file
# Saves font.json and reruns the current theme; nothing in the repo is rewritten.
use lib.nu [status-record status-print notify cycle-next]
use ../../configs/core/wallust/font.nu [font-load font-save]

const DOT = path self ../dot.nu
const UI_SIZE_MIN = 6
const SIZE_MIN = 1
const SIZE_MAX = 48
const SHORTLIST = [
    "Kode Mono" "Tektur" "0xProto Nerd Font" "JetBrainsMono Nerd Font" "FiraCode Nerd Font" "Hack Nerd Font"
    "CaskaydiaCove Nerd Font" "CommitMono Nerd Font"
]

def families-installed []: nothing -> list<string> {
    ^fc-list : family | lines | split row "," | str trim | compact --empty | uniq | sort
}

def shortlist []: nothing -> list<string> { let installed = families-installed; $SHORTLIST | where $it in $installed }

# Saves the change and reruns the current theme; quickshell follows font.json live, nvim and firefox on their start.
def font-set [changes: record, title: string, value: string]: nothing -> nothing {
    font-save $changes
    let wallpaper = ^readlink -f ($nu.home-dir | path join .cache wal wallpaper) | complete | get stdout | str trim
    if ($wallpaper | path exists) { ^nu --no-config-file $DOT theme $wallpaper } else {
        print -e "no theme yet: the font applies with the first dot theme"
    }
    notify $title $value
}

def size-parse [size: string, min: int]: nothing -> int {
    if $size !~ '^[0-9]+$' or ($size | into int) < $min {
        error make {msg: $"usage: toggle-font.nu set-size|set-ui-size <n>, n at least ($min)"}
    }
    $size | into int
}

def "main get" [--json] {
    let font = font-load
    status-print (status-record Font $font.family --text $"($font.family) ($font.size)") $json
}
def "main size" [] { (font-load).size }
def "main ui-size" [] { (font-load).ui_size }
def "main list" [] { print (families-installed | str join "\n") }
def "main shortlist" [] { print (shortlist | str join "\n") }

# rows shaped like `dot set --json`, each with the verb that sets it, for the settings window
def "main options" [] {
    let font = font-load
    [
        {
            key: family, label: Family, type: string, choices: (families-installed), value: $font.family, set: set
            doc: "terminals and editors take its monospace partner"
        }
        {
            key: size, label: Size, type: int, min: $SIZE_MIN, max: $SIZE_MAX, value: $font.size, set: set-size
            doc: "terminals, editors and the shell"
        }
        {
            key: ui-size, label: "UI size", type: int, min: $UI_SIZE_MIN, max: $SIZE_MAX, value: $font.ui_size
            set: set-ui-size, doc: "gtk and qt apps, browsers, discord and spotify"
        }
    ] | to json --raw
}

def "main set" [...family: string] {
    let family = $family | str join " "
    if ($family | is-empty) { error make {msg: "usage: toggle-font.nu set <family>"} }
    if $family not-in (families-installed) { error make {msg: $"font family not installed: ($family)"} }
    font-set {family: $family} Font $family
}

def "main set-size" [size: string] {
    let size = size-parse $size $SIZE_MIN
    font-set {size: $size} "Font size" ($size | into string)
}

def "main set-ui-size" [size: string] {
    let size = size-parse $size $UI_SIZE_MIN
    font-set {ui_size: $size} "UI font size" ($size | into string)
}

def "main toggle" [] {
    let available = shortlist
    if ($available | is-empty) {
        print -e "no shortlist font installed"
        return
    }
    let next = $available | cycle-next (font-load).family
    font-set {family: $next} Font $next
}

def main [] { main get }
