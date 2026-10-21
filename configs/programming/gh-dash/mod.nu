use module.nu *

export const meta = {packages: {pacman: [gh-dash gh-enhance-bin]}}

const CONFIG = ".config/gh-dash/config.yml"
const SELECTED_MIX = 0.12

def mix [a: string, b: string, t: float]: nothing -> string {
    let channels = {|hex| [1 3 5] | each {|i| $"0x($hex | str substring $i..($i + 1))" | into int } }
    do $channels $a | zip (do $channels $b) | each {|c| $c.0 * (1 - $t) + $c.1 * $t | math round | into binary | first 1 | encode hex }
    | str join | $"#($in | str lowercase)"
}

# The theme verb and link render the same file, so neither sees the other's write as drift.
def config [] {
    let p = palette-load
    let base = open config.yml
    let text = if $p == null { $base } else {
        let accent = $p.c4 | str lowercase
        $base | upsert theme.colors {
            text: {primary: ($p.fg | str lowercase), secondary: $accent, inverted: ($p.bg | str lowercase), faint: ($p.c8 | str lowercase), warning: ($p.c3 | str lowercase), success: ($p.c2 | str lowercase)}
            background: {selected: (mix ($p.bg | str lowercase) $accent $SELECTED_MIX)}
            border: {primary: $accent, secondary: ($p.c8 | str lowercase), faint: ($p.c0 | str lowercase)}
        }
    }
    file-text ($nu.home-dir | path join $CONFIG) ($text | to yaml)
}

export def link [cfg: record] {
    config
}

export def theme [cfg: record, wallpaper: string] {
    config
}
