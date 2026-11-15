use module.nu *
use ../../core/wallust/font.nu [font-load]
use ../../core/wallust/editor.nu [editor-roles]
use ../../core/wallust/palette.nu [condition-bg palette-rgb rgb-to-hex]

export const meta = {packages: {pacman: [zed]}}

# Merged: zed's UI edits survive, the repo's keys and the font win.
def settings []: nothing -> record {
    let font = font-load
    let edits = open settings.json | merge {buffer_font_family: $font.mono, buffer_font_size: $font.size}
        | items {|k, v| json-set [$k] $v }
    json-merge (xdg config zed settings.json) $edits
}

export def link [cfg: record] {
    [(files-into (xdg config zed) keymap.json) (settings)]
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-rgb zed
    if $p == null { return (settings) }
    let hex = $p | update cells { rgb-to-hex --prefix "#" }
    let ansi = [black red green yellow blue magenta cyan white] | enumerate | each {|c|
        [[$"terminal.ansi.($c.item)" ($hex | get $"c($c.index)")] [$"terminal.ansi.bright_($c.item)" ($hex | get $"c($c.index + 8)")]]
    } | flatten | into record
    let r = $p | editor-roles ($p.bg | condition-bg)
    let syntax = {
        attribute: $r.builtin boolean: $r.constant comment: $r.comment "comment.doc": $r.comment constant: $r.constant
        constructor: $r.type embedded: $r.fg enum: $r.type function: $r.function hint: $r.hint keyword: $r.keyword
        label: $r.keyword link_text: $r.function link_uri: $r.function number: $r.constant operator: $r.punctuation
        predictive: $r.comment preproc: $r.builtin primary: $r.fg property: $r.property punctuation: $r.punctuation
        "punctuation.bracket": $r.punctuation "punctuation.delimiter": $r.punctuation
        "punctuation.list_marker": $r.keyword "punctuation.special": $r.builtin string: $r.string
        "string.escape": $r.builtin "string.regex": $r.builtin "string.special": $r.builtin
        "string.special.symbol": $r.constant tag: $r.tag "text.literal": $r.string title: $r.function type: $r.type
        variable: $r.fg "variable.special": $r.tag variant: $r.constant
    } | update cells {|v| {color: $v} }
    let italic = {comment: {font_style: italic} "comment.doc": {font_style: italic}}
    let style = {
        background: $r.bg
        "editor.background": $r.bg
        "editor.foreground": $r.fg
        "editor.gutter.background": $r.bg
        "editor.active_line.background": $r.current
        "editor.highlighted_line.background": $r.current
        "editor.line_number": $r.line_number
        "editor.active_line_number": $r.function
        "editor.indent_guide": $r.border
        "editor.indent_guide_active": $r.line_number
        "editor.invisible": $r.border
        "editor.wrap_guide": $r.border
        "editor.active_wrap_guide": $r.line_number
        "editor.subheader.background": $r.surface
        "editor.document_highlight.read_background": $r.current
        "editor.document_highlight.write_background": $r.selection
        "search.match_background": $r.search
        text: $r.fg
        "text.muted": $r.comment
        "text.placeholder": $r.comment
        "text.disabled": $r.line_number
        "text.accent": $r.function
        icon: $r.fg
        "icon.muted": $r.comment
        "icon.accent": $r.function
        "link_text.hover": $r.function
        border: $r.border
        "border.variant": $r.current
        "border.focused": $r.function
        "border.selected": $r.function
        "element.background": $r.surface
        "element.hover": $r.surface_hover
        "element.selected": $r.current
        "element.active": $r.selection
        "ghost_element.hover": $r.surface_hover
        "ghost_element.selected": $r.current
        "surface.background": $r.bg
        "elevated_surface.background": $r.surface
        "panel.background": $r.bg
        "tab.active_background": $r.bg
        "tab.inactive_background": $r.surface
        "tab_bar.background": $r.surface
        "status_bar.background": $r.surface
        "title_bar.background": $r.surface
        "toolbar.background": $r.bg
        "scrollbar.thumb.background": $r.border
        "scrollbar.track.background": $r.bg
        "terminal.background": $r.bg
        "terminal.foreground": $r.fg
        error: $r.error
        warning: $r.warn
        info: $r.info
        hint: $r.hint
        success: $r.ok
        created: $r.added
        modified: $r.changed
        deleted: $r.removed
        conflict: $r.warn
        ignored: $r.line_number
        hidden: $r.line_number
        "version_control.added": $r.added
        "version_control.modified": $r.changed
        "version_control.deleted": $r.removed
        players: [{cursor: $r.fg, selection: $r.selection, background: $r.function}]
    } | merge $ansi | merge {syntax: ($syntax | merge deep $italic)}
    let theme = {
        "$schema": "https://zed.dev/schema/themes/v0.2.0.json"
        name: Wallust
        author: "wallust (generated)"
        themes: [{name: Wallust, appearance: (if $r.light { "light" } else { "dark" }), style: $style}]
    }
    [
        (file-text (xdg config zed themes wallust.json) $"($theme | to json --indent 2)\n" --generated)
        (settings)
    ]
}
