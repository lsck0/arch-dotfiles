#!/usr/bin/env -S nu --no-config-file
use lib.nu [notify cycle-next state-file state-set]

const GHOSTTY = path self ../../configs/desktop/ghostty/config
const ZED = path self ../../configs/programming/zed/settings.json
const EMACS = path self ../../configs/programming/emacs/early-init.el
const DISCORD = path self ../../configs/socials/discord/wal.theme.css
const SPOTIFY = path self ../../configs/socials/spotify/user.css
const KITTY = path self ../../configs/desktop/kitty/kitty.conf
const QUTEBROWSER = path self ../../configs/desktop/qutebrowser/config.py
const QUTEBROWSER_STARTPAGE = path self ../../configs/desktop/qutebrowser/startpage.html
const QUICKSHELL_THEME = path self ../../configs/desktop/quickshell/theme.json
const VSCODE = path self ../../configs/programming/vscode/settings.json
const ZATHURA = path self ../../configs/desktop/zathura/zathurarc
const FIREFOX_CHROME = path self ../../configs/desktop/firefox/userChrome.css
const GTK_CSS = path self ../../configs/desktop/gtk/gtk.css
const DOT = path self ../dot.nu
const RELINKED = [desktop/zathura desktop/qutebrowser programming/zed programming/emacs]
const RETHEMED = [
    desktop/kitty desktop/ghostty programming/emacs programming/vscode socials/spotify socials/discord desktop/gtk
    desktop/plasma desktop/zathura desktop/qutebrowser
]
const GTK_DIRS = [gtk-3.0 gtk-4.0]
const KDE_FONT_KEYS = [
    [group key];
    [General font] [General fixed] [General menuFont] [General smallestReadableFont] [General toolBarFont] [WM activeFont]
]
const KDE_SMALLEST_OFFSET = 2
const UI_SIZE_MIN = 6
const UI_SIZE_DEFAULT = 10
const SIZE_MIN = 1
const SIZE_MAX = 48
const NVIM_GUIFONT_DEFAULT = "Kode Mono:h16"
const SHORTLIST = [
    "Kode Mono" "Tektur" "0xProto Nerd Font" "JetBrainsMono Nerd Font" "FiraCode Nerd Font" "Hack Nerd Font"
    "CaskaydiaCove Nerd Font" "CommitMono Nerd Font"
]
const MONO_PARTNERS = {Tektur: "Kode Mono"}

def ghostty-get [key: string]: nothing -> string {
    open --raw $GHOSTTY | parse --regex ('(?m)^' + $key + ' = (?<value>.*)$') | get value.0
}

def family-get []: nothing -> string { try { open $QUICKSHELL_THEME | get font.family } catch { ghostty-get font-family } }

def size-get []: nothing -> int { ghostty-get font-size | into int }

def ui-size-get []: nothing -> int {
    let size = ^gsettings get org.gnome.desktop.interface font-name | complete | get stdout | str trim | str trim --char "'" | split row " " | last
    if $size =~ '^[0-9]+$' { $size | into int } else { $UI_SIZE_DEFAULT }
}

def families-installed []: nothing -> list<string> {
    ^fc-list : family | lines | split row "," | str trim | compact --empty | uniq | sort
}

def mono-family [family: string]: nothing -> string {
    let partner = $MONO_PARTNERS | get --optional $family
    if $partner != null and $partner in (families-installed) { $partner } else { $family }
}

def shortlist []: nothing -> list<string> { let installed = families-installed; $SHORTLIST | where $it in $installed }

def files-edit [edits: table]: nothing -> nothing {
    for edit in $edits {
        open --raw $edit.file | str replace --regex --all=$edit.all $edit.pattern $edit.replacement | save --force $edit.file
    }
}

def quickshell-theme-set [key: string, value: any]: nothing -> nothing {
    open $QUICKSHELL_THEME | upsert ([font $key] | into cell-path) $value | $"($in | to json --indent 2)\n" | save --force $QUICKSHELL_THEME
}

def nvim-guifont-set [family: any, size: any]: nothing -> nothing {
    let current = try { open --raw (state-file nvim-guifont) | str trim } catch { $NVIM_GUIFONT_DEFAULT } | parse "{family}:h{size}" | first
    state-set nvim-guifont $"($family | default $current.family):h($size | default $current.size)"
}

def gtk-font-set [family: any, size: any]: nothing -> nothing {
    let family = $family | default (family-get)
    for dir in $GTK_DIRS {
        let ini = $nu.home-dir | path join .config $dir settings.ini
        if not ($ini | path exists) { continue }
        let text = open --raw $ini
        let own = $text | parse --regex '(?m)^gtk-font-name=.* (?<size>[0-9]+)$' | get size.0?
        let line = $"gtk-font-name=($family) ($size | default $own | default (ui-size-get))"
        if $text =~ '(?m)^gtk-font-name=' {
            $text | str replace --all --regex '(?m)^gtk-font-name=.*$' $line
        } else {
            $text | str replace --regex '(?m)^\[Settings\]$' $"[Settings]\n($line)"
        } | save --force $ini
    }
    ^gsettings set org.gnome.desktop.interface font-name $"($family) ($size | default (ui-size-get))" | complete | ignore
}

def kde-font-set [family: any, size: any]: nothing -> nothing {
    if (which kwriteconfig6 | is-empty) { return }
    for entry in $KDE_FONT_KEYS {
        let current = ^kreadconfig6 --file kdeglobals --group $entry.group --key $entry.key | complete | get stdout | str trim
        if ($current | is-empty) { continue }
        let fields = $current | split row ","
        let size = if $size == null { $fields.1 } else if $entry.key == smallestReadableFont { $size - $KDE_SMALLEST_OFFSET } else { $size }
        let font = $fields | update 0 ($family | default $fields.0) | update 1 ($size | into string) | str join ","
        ^kwriteconfig6 --file kdeglobals --group $entry.group --key $entry.key $font
    }
}

def family-apply [family: string]: nothing -> nothing {
    let mono = mono-family $family
    files-edit ([
        [file pattern replacement all];
        [$GHOSTTY '(?m)^font-family = .*$' $"font-family = ($mono)" false]
        [$ZED '"buffer_font_family": "[^"]*"' $'"buffer_font_family": "($mono)"' true]
        [$ZED '"ui_font_family": "[^"]*"' $'"ui_font_family": "($family)"' true]
        [$ZED '"font_family": "[^"]*"' $'"font_family": "($mono)"' true]
        [$EMACS '(?m)^\(defvar my/font-family ".*"\)' $"\(defvar my/font-family \"($mono)\"\)" true]
        [$DISCORD '(?m)^(\s*)--font: ".*";' $'${1}--font: "($family)";' true]
        [$SPOTIFY 'font-family: "[^"]*", "Symbols Nerd Font"' $'font-family: "($family)", "Symbols Nerd Font"' true]
        [$KITTY '(?m)^font_family .*$' $"font_family ($mono)" true]
        [$QUTEBROWSER '(?m)^c\.fonts\.default_family = ".*"' $'c.fonts.default_family = "($family)"' true]
        [$VSCODE `"editor\.fontFamily": "'[^']*'` $"\"editor.fontFamily\": \"'($mono)'" true]
        [$ZATHURA '(?m)^set font "[^"]*( [0-9]*)"' $'set font "($family)${1}"' true]
        [$FIREFOX_CHROME '--rtk-chrome-font: "[^"]*",' $'--rtk-chrome-font: "($family)",' true]
        [$GTK_CSS 'font-family: "[^"]*", sans-serif;' $'font-family: "($family)", sans-serif;' true]
        [$QUTEBROWSER_STARTPAGE 'font-family: "[^"]*", monospace;' $'font-family: "($family)", monospace;' true]
    ])
    nvim-guifont-set $mono null
    quickshell-theme-set family $family
    gtk-font-set $family null
    kde-font-set $family null
}

def size-apply [size: int]: nothing -> nothing {
    files-edit [
        [file pattern replacement all];
        [$GHOSTTY '(?m)^font-size = .*$' $"font-size = ($size)" true]
        [$KITTY '(?m)^font_size .*$' $"font_size ($size)" true]
        [$ZED '"buffer_font_size": [0-9.]*' $'"buffer_font_size": ($size)' true]
        [$ZED '"ui_font_size": [0-9.]*' $'"ui_font_size": ($size)' true]
        [$ZED '"font_size": [0-9.]*' $'"font_size": ($size)' true]
        [$EMACS '(?m)^\(defvar my/font-size .*\)' $"\(defvar my/font-size ($size)\)" true]
        [$VSCODE '"editor\.fontSize": [0-9.]*' $'"editor.fontSize": ($size)' true]
    ]
    nvim-guifont-set null $size
    quickshell-theme-set size $size
}

def ui-size-apply [size: int]: nothing -> nothing {
    let scale = $size / $UI_SIZE_DEFAULT | math round --precision 2
    files-edit [
        [file pattern replacement all];
        [$QUTEBROWSER '(?m)^c\.fonts\.default_size = ".*"' $'c.fonts.default_size = "($size)pt"' true]
        [$ZATHURA '(?m)^(set font "[^"]*) [0-9]+"' $'${1} ($size)"' true]
        [$FIREFOX_CHROME '--rtk-chrome-font-size: [0-9]+pt;' $'--rtk-chrome-font-size: ($size)pt;' true]
        [$DISCORD '--font-scale: [0-9.]+;' $'--font-scale: ($scale);' true]
        [$SPOTIFY '--font-scale: [0-9.]+;' $'--font-scale: ($scale);' true]
    ]
    gtk-font-set null $size
    kde-font-set null $size
}

def live-apply []: nothing -> nothing {
    let wallpaper = ^readlink -f ($nu.home-dir | path join .cache wal wallpaper) | complete | get stdout | str trim
    let dot = $"^nu --no-config-file ($DOT | to nuon)"
    let link = $"($dot) apply --user ...($RELINKED | to nuon)"
    let theme = if ($wallpaper | path exists) { $"; ($dot) internal theme apply ($wallpaper | to nuon) ...($RETHEMED | to nuon)" } else { "" }
    ^setsid -f nu --no-config-file -c $"($link)($theme)" out+err> /dev/null
}

def reload-hint []: nothing -> nothing {
    live-apply
    let theme = ^gsettings get org.gnome.desktop.interface gtk-theme | complete | get stdout | str trim | str trim --char "'"
    if ($theme | is-not-empty) {
        ^gsettings set org.gnome.desktop.interface gtk-theme '' | complete
        ^gsettings set org.gnome.desktop.interface gtk-theme $theme | complete
    }
    print -e (
        "quickshell, terminals, emacs, vscodium, zed, spotify, discord, zathura and qutebrowser: applied live; "
        + "gtk and qt/kde: live where the app follows the desktop, else on its next start; nvim and firefox: next start"
    )
}

def family-set [family: string]: nothing -> nothing {
    family-apply $family
    notify Font $family
    reload-hint
}

def size-parse [size: string, min: int]: nothing -> int {
    if $size !~ '^[0-9]+$' or ($size | into int) < $min {
        error make {msg: $"usage: toggle-font.nu set-size|set-ui-size <n>, n at least ($min)"}
    }
    $size | into int
}

def "main get" [] { family-get }
def "main size" [] { size-get }
def "main ui-size" [] { ui-size-get }
def "main label" [] { $"󰛖 Font: (family-get) (ghostty-get font-size)" }
def "main list" [] { print (families-installed | str join "\n") }
def "main shortlist" [] { print (shortlist | str join "\n") }

# rows shaped like `dot set --json`, each with the verb that sets it, for the settings window
def "main options" [] {
    [
        {
            key: family, label: Family, type: string, choices: (families-installed), value: (family-get), set: set
            doc: "terminals and editors take its monospace partner"
        }
        {
            key: size, label: Size, type: int, min: $SIZE_MIN, max: $SIZE_MAX, value: (size-get), set: set-size
            doc: "terminals, editors and the shell"
        }
        {
            key: ui-size, label: "UI size", type: int, min: $UI_SIZE_MIN, max: $SIZE_MAX, value: (ui-size-get)
            set: set-ui-size, doc: "gtk and qt apps"
        }
    ] | to json --raw
}

def "main set" [...family: string] {
    let family = $family | str join " "
    if ($family | is-empty) { error make {msg: "usage: toggle-font.nu set <family>"} }
    if $family not-in (families-installed) { error make {msg: $"font family not installed: ($family)"} }
    family-set $family
}

def "main set-size" [size: string] {
    let size = size-parse $size $SIZE_MIN
    size-apply $size
    notify "Font size" ($size | into string)
    reload-hint
}

def "main set-ui-size" [size: string] {
    let size = size-parse $size $UI_SIZE_MIN
    ui-size-apply $size
    notify "UI font size" ($size | into string)
    reload-hint
}

def "main toggle" [] {
    let available = shortlist
    if ($available | is-empty) {
        print -e "no shortlist font installed"
        return
    }
    family-set ($available | cycle-next (family-get))
}

def main [] { main label }
