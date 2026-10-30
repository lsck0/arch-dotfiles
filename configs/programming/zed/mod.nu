use module.nu *
use ../../core/wallust/font.nu [font-load]
use ../../core/wallust/palette.nu [hex-to-rgb readable-on rgb-to-hex shade]

export const meta = {packages: {pacman: [zed]}}

const CONFIG_DIR = ".config/zed"

export def link [cfg: record] {
    [(files-into ($nu.home-dir | path join $CONFIG_DIR) keymap.json) (settings)]
}

# Merged: zed's UI edits survive, the repo's keys and the font win.
def settings []: nothing -> record {
    let font = font-load
    let edits = open settings.json | merge {buffer_font_family: $font.mono, buffer_font_size: $font.size}
        | items {|k, v| json-set [$k] $v }
    json-merge ($nu.home-dir | path join $CONFIG_DIR settings.json) $edits
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return (settings) }
    let ansi = [black red green yellow blue magenta cyan white] | enumerate | each {|c|
        [[$"terminal.ansi.($c.item)" ($p | get $"c($c.index)")] [$"terminal.ansi.bright_($c.item)" ($p | get $"c($c.index + 8)")]]
    } | flatten | into record
    let bg = $p.bg_conditioned | hex-to-rgb
    let chrome = $bg | shade 0.045 | rgb-to-hex --prefix "#"
    let hover = $bg | shade 0.08 | rgb-to-hex --prefix "#"
    let current = $bg | shade 0.11
    let current_hex = $current | rgb-to-hex --prefix "#"
    let readable = {|slot| $p | get $slot | hex-to-rgb | readable-on $bg | rgb-to-hex --prefix "#" }
    let style = {
        background: $p.bg_conditioned
        "editor.background": $p.bg_conditioned
        "editor.foreground": $p.fg
        "editor.gutter.background": $p.bg_conditioned
        "editor.active_line.background": $current_hex
        "editor.line_number": $p.c8
        "editor.active_line_number": ($p.fg | hex-to-rgb | readable-on $current | rgb-to-hex --prefix "#")
        text: $p.fg
        "text.muted": $p.c8
        "text.accent": (do $readable c4)
        border: $p.c8
        "border.variant": $current_hex
        "element.background": $chrome
        "element.hover": $hover
        "element.selected": $current_hex
        "surface.background": $p.bg_conditioned
        "panel.background": $p.bg_conditioned
        "tab.active_background": $p.bg_conditioned
        "tab.inactive_background": $chrome
        "tab_bar.background": $chrome
        "status_bar.background": $chrome
        "title_bar.background": $chrome
        "toolbar.background": $p.bg_conditioned
        "terminal.background": $p.bg_conditioned
        "terminal.foreground": $p.fg
    } | merge $ansi | merge {
        syntax: {
            comment: {color: $p.c8}
            string: {color: (do $readable c2)}
            keyword: {color: (do $readable c4)}
            function: {color: (do $readable c3)}
            type: {color: (do $readable c6)}
            variable: {color: $p.fg}
            constant: {color: (do $readable c5)}
            number: {color: (do $readable c5)}
        }
    }
    let theme = {
        "$schema": "https://zed.dev/schema/themes/v0.2.0.json"
        name: Wallust
        author: "wallust (generated)"
        themes: [{name: Wallust, appearance: (if $p.light == "1" { "light" } else { "dark" }), style: $style}]
    }
    [
        (file-text ($nu.home-dir | path join $CONFIG_DIR themes wallust.json) $"($theme | to json --indent 2)\n" --generated)
        (settings)
    ]
}
