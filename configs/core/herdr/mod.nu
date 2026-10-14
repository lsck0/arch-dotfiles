use module.nu *
use ../wallust/palette.nu [palette-slots hex-to-rgb rgb-to-hex tone-map mix]

const CONFIG = ".config/herdr/config.toml"
const BLOCK = '(?s)(# BEGIN PYWAL THEME\n).*?(# END PYWAL THEME)'
# herdr wants a lighter dark floor than the clamp band; a light theme's conditioned bg is already right
const DARK_FLOOR = 0.16
# the surfaces are fg blended over that bg
const BLENDS = {
    active_row_bg: 0.06, selection_bg: 0.11, surface_dim: 0.0, surface0: 0.08, surface1: 0.14, overlay0: 0.22
    overlay1: 0.34, subtext0: 0.65
}
const SLOTS = [bg fg c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15 light bg_conditioned]
const WAL_COLORS = ".cache/wal/colors.json"

# config.toml with its pywal block filled from the palette; the whole file is rendered, so a switch never touches the
# repo
def config-text []: nothing -> string {
    let source = open --raw config.toml
    if not ($nu.home-dir | path join $WAL_COLORS | path exists) { return $source }
    let p = $SLOTS | zip (palette-slots) | into record
    let bg = if $p.light == "1" { $p.bg_conditioned } else {
        $p.bg_conditioned | hex-to-rgb | tone-map --lo $DARK_FLOOR --hi 1.0 | rgb-to-hex --prefix "#"
    }
    let blend = {|t| mix ($bg | hex-to-rgb) ($p.fg | hex-to-rgb) $t | rgb-to-hex --prefix "#" | str lowercase }
    let s = $BLENDS | items {|k, t| {k: $k, v: (do $blend $t)} } | transpose -r -d
    let theme = [
        [sidebar_bg reset] [panel_bg reset] [active_row_bg $s.active_row_bg] [selection_bg $s.selection_bg]
        [accent $p.c4] [red $p.c1] [green $p.c2] [surface_dim $s.surface_dim] [surface0 $s.surface0]
        [surface1 $s.surface1] [overlay0 $s.overlay0] [overlay1 $s.overlay1] [text $p.fg] [subtext0 $s.subtext0]
        [yellow $p.c3] [blue $p.c4] [mauve $p.c5] [teal $p.c6] [peach $p.c11]
    ]
    let block = $theme | each {|kv| $'($kv.0) = "($kv.1)"' } | prepend "[theme.custom]" | str join "\n"
    $source | str replace --regex $BLOCK $"${1}($block)\n${2}"
}

def config []: nothing -> list<record> {
    [(file-text ($nu.home-dir | path join $CONFIG) (config-text) --mode 600 --generated) (step herdr-reload)]
}

# no running herdr server is fine, the next one reads the file
export def herdr-reload []: nothing -> nothing {
    try { ^herdr server reload-config o+e>| ignore }
}

export def link [cfg: record] {
    # invoked bare by tmux/nvim/viewers
    [(config) (link-commands herdr-open.nu)]
}

export def theme [cfg: record, wallpaper: string] {
    config
}
