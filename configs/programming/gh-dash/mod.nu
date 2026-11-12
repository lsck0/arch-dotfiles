use module.nu *
use ../../core/wallust/palette.nu [hex-to-rgb mix rgb-to-hex]

export const meta = {packages: {pacman: [gh-dash gh-enhance-bin]}}

const SELECTED_MIX = 0.12

# The theme verb and link render the same file, so neither sees the other's write as drift.
def config-render []: nothing -> record {
    let base = open config.yml
    let p = palette-load
    let merged = if $p == null { $base } else {
        let c = $p | update cells { str lowercase }
        $base | upsert theme.colors {
            text: {primary: $c.fg, secondary: $c.c4, inverted: $c.bg, faint: $c.c8, warning: $c.c3, success: $c.c2}
            background: {selected: (mix ($c.bg | hex-to-rgb) ($c.c4 | hex-to-rgb) $SELECTED_MIX | rgb-to-hex --prefix '#')}
            border: {primary: $c.c4, secondary: $c.c8, faint: $c.c0}
        }
    }
    file-text (xdg config gh-dash config.yml) ($merged | to yaml)
}

export def link [cfg: record] {
    [(shell-aliases gh-dash) (config-render)]
}

export def theme [cfg: record, wallpaper: string] {
    config-render
}
