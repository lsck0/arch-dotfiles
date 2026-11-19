use module.nu *
use ../../core/wallust/editor.nu [editor-roles]
use ../../core/wallust/palette.nu [palette-rgb]

export const meta = {
    packages: {
        pacman: [
            appimagetool-git ast-grep bat bc cdecl contrast cppcheck csvi-bin expect figlet glow go-yq gonzo graphviz
            grex heh help2man hyperfine identity jless jrnl lazyjira-bin lazymake-bin ls-horizons mdbook minisign
            mermaid-cli miller osmium-tool pastel phoronix-test-suite pipeline-gtk resvg rgx ripgrep serpl slides-git
            tesseract tesseract-data-deu tesseract-data-eng time tokei tokui vale yozefu
        ]
    }
}

export def link [cfg: record] {
    [
        (shell-aliases devtools)
        (files-into (xdg config environment.d) bat.conf)
    ]
}

# bat's own theme from the editor roles, so its comments read as nvim's do (ansi's color8 sits near 3:1); delta and
# the man pager use it through bat's cache.
const BAT_THEME = "wal"
# tmTheme scopes per role: the textmate names bat's syntaxes emit
const BAT_SCOPES = [
    [role scope];
    [comment "comment, punctuation.definition.comment"]
    [keyword "keyword, storage, keyword.operator.word"]
    [function "entity.name.function, support.function, meta.function-call"]
    [string "string, punctuation.definition.string"]
    [type "entity.name.type, entity.name.class, support.type, support.class, storage.type"]
    [constant "constant, constant.numeric, constant.language, constant.character"]
    [builtin "support.constant, variable.language"]
    [tag "entity.name.tag, markup.heading"]
    [property "entity.other.attribute-name, variable.other.member, meta.property-name"]
    [parameter "variable.parameter"]
    [punctuation "punctuation, keyword.operator"]
    [error "invalid"]
    [added "markup.inserted"]
    [removed "markup.deleted"]
    [changed "markup.changed"]
]

def tm-dict [entries: record]: nothing -> string {
    $entries | items {|k, v| $"<key>($k)</key><string>($v)</string>" } | str join ""
}

def bat-theme [roles: record]: nothing -> string {
    let global = tm-dict {
        background: $roles.bg, foreground: $roles.fg, caret: $roles.fg, selection: $roles.selection
        lineHighlight: $roles.current, gutterForeground: $roles.line_number
    }
    let rules = $BAT_SCOPES | each {|r|
        $"<dict><key>scope</key><string>($r.scope)</string><key>settings</key><dict>(tm-dict {foreground: ($roles | get $r.role)})(if $r.role == comment { '<key>fontStyle</key><string>italic</string>' } else { '' })</dict></dict>"
    } | str join "\n"
    [
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        $"<plist version=\"1.0\"><dict><key>name</key><string>($BAT_THEME)</string><key>settings</key><array>"
        $"<dict><key>settings</key><dict>($global)</dict></dict>"
        $rules
        "</array></dict></plist>"
    ] | str join "\n"
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-rgb bat
    if $p == null { return [] }
    let file = xdg config bat themes $"($BAT_THEME).tmTheme"
    [(file-text $file $"(bat-theme ($p | editor-roles $p.bg))\n" --generated --then [bat cache --build])]
}
