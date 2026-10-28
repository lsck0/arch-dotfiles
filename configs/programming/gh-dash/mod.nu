use module.nu *
use ../../core/wallust/palette.nu [hex-to-rgb mix rgb-to-hex]

export const meta = {packages: {pacman: [gh-dash gh-enhance-bin]}}

const SELECTED_MIX = 0.12

# The theme verb and link render the same file, so neither sees the other's write as drift.
def config [] {
    let p = palette-load
    let base = open config.yml
    let text = if $p == null { $base } else {
        let accent = $p.c4 | str lowercase
        $base | upsert theme.colors {
            text: {primary: ($p.fg | str lowercase), secondary: $accent, inverted: ($p.bg | str lowercase), faint: ($p.c8 | str lowercase), warning: ($p.c3 | str lowercase), success: ($p.c2 | str lowercase)}
            background: {selected: (mix ($p.bg | hex-to-rgb) ($accent | hex-to-rgb) $SELECTED_MIX | rgb-to-hex --prefix '#')}
            border: {primary: $accent, secondary: ($p.c8 | str lowercase), faint: ($p.c0 | str lowercase)}
        }
    }
    file-text (xdg config gh-dash config.yml) ($text | to yaml)
}

export def link [cfg: record] {
    config
}

export def theme [cfg: record, wallpaper: string] {
    config
}
