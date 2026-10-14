use module.nu *

export const meta = {packages: {pacman: [zed]}}

const CONFIG_DIR = ".config/zed"

export def link [cfg: record] {
    files-into ($nu.home-dir | path join $CONFIG_DIR) settings.json keymap.json
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    let ansi = [black red green yellow blue magenta cyan white] | enumerate | each {|c|
        [[$"terminal.ansi.($c.item)" ($p | get $"c($c.index)")] [$"terminal.ansi.bright_($c.item)" ($p | get $"c($c.index + 8)")]]
    } | flatten | into record
    let style = {
        background: $p.bg_conditioned
        "editor.background": $p.bg_conditioned
        "editor.foreground": $p.fg
        "editor.gutter.background": $p.bg_conditioned
        "editor.active_line.background": $p.c8
        "editor.line_number": $p.c8
        "editor.active_line_number": $p.fg
        text: $p.fg
        "text.muted": $p.c8
        "text.accent": $p.c4
        border: $p.c8
        "border.variant": $p.c0
        "element.background": $p.c0
        "element.hover": $p.c8
        "element.selected": $p.c4
        "surface.background": $p.bg_conditioned
        "panel.background": $p.bg_conditioned
        "tab.active_background": $p.bg_conditioned
        "tab.inactive_background": $p.c0
        "tab_bar.background": $p.c0
        "status_bar.background": $p.c0
        "title_bar.background": $p.c0
        "toolbar.background": $p.bg_conditioned
        "terminal.background": $p.bg_conditioned
        "terminal.foreground": $p.fg
    } | merge $ansi | merge {
        syntax: {
            comment: {color: $p.c8}
            string: {color: $p.c2}
            keyword: {color: $p.c4}
            function: {color: $p.c3}
            type: {color: $p.c6}
            variable: {color: $p.fg}
            constant: {color: $p.c5}
            number: {color: $p.c5}
        }
    }
    let theme = {
        "$schema": "https://zed.dev/schema/themes/v0.2.0.json"
        name: Pywal
        author: "pywal (generated)"
        themes: [{name: Pywal, appearance: (if $p.light == "1" { "light" } else { "dark" }), style: $style}]
    }
    file-text ($nu.home-dir | path join $CONFIG_DIR themes pywal.json) $"($theme | to json --indent 2)\n" --generated
}
