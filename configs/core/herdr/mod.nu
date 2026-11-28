use module.nu *
use ../wallust/scripts/palette.nu [ACCENT_RATIO TEXT_RATIO blend-floor hex-to-rgb mix readable-on rgb-to-hex tone-map]

export const meta = {deps: [core/cli core/wallust], packages: {pacman: [herdr-bin]}}

export const options = {
    prefix: {
        type: string
        default: ctrl+q
        doc: "herdr prefix key, in herdr key syntax"
        label: "Prefix key"
        scope: user
    }
    sidebar_width: {
        type: int
        default: 20
        doc: "Sidebar width in columns"
        label: "Sidebar width"
        min: 14
        max: 30
        scope: user
    }
}

const BLOCK = '(?s)(# BEGIN PYWAL THEME\n).*?(# END PYWAL THEME)'
const DARK_FLOOR = 0.16
const BLENDS = {
    active_row_bg: 0.06, selection_bg: 0.11, surface_dim: 0.0, surface0: 0.08, surface1: 0.14, overlay0: 0.22
    overlay1: 0.34, subtext0: 0.65
}
# herdr draws text in these: overlay0 the secondary lines (a row's branch and agent, unfocused rows, tab names),
# overlay1 the selected row's number, subtext0 unfocused agent names. A blend short of its floor on selection_bg, the
# surface nearest the foreground that text sits on, is raised toward the foreground in TEXT_STEP until it reaches it.
export const TEXT_FLOORS = {overlay0: $ACCENT_RATIO, overlay1: $TEXT_RATIO, subtext0: $TEXT_RATIO}
const TEXT_STEP = 0.02
const RELOAD = path self scripts/herdr-reload.nu

# The first blend of fg into bg from t up that reaches ratio on surface; when fg itself falls short, fg walked toward
# white or black.
def text-blend [bg: list<float>, fg: list<float>, surface: list<float>, t: float, ratio: float]: nothing -> list<float> {
    let found = blend-floor $bg $fg $surface $t $TEXT_STEP $ratio
    if $found == null { $fg | readable-on $surface --ratio $ratio } else { mix $bg $fg $found }
}

# The [theme.custom] keys and colours for palette p (a `palette-load` record).
export def theme-custom [p: record]: nothing -> list<list<string>> {
    let bg = if $p.light == "1" { $p.bg_conditioned } else {
        $p.bg_conditioned | hex-to-rgb | tone-map --lo $DARK_FLOOR --hi 1.0 | rgb-to-hex --prefix "#"
    }
    let bg_rgb = $bg | hex-to-rgb
    let fg_rgb = $p.fg | hex-to-rgb
    let surface = mix $bg_rgb $fg_rgb $BLENDS.selection_bg
    let rgb = $BLENDS | items {|k, t|
        let floor = $TEXT_FLOORS | get --optional $k
        [$k (if $floor == null { mix $bg_rgb $fg_rgb $t } else { text-blend $bg_rgb $fg_rgb $surface $t $floor })]
    } | into record
    let s = $rgb | update cells { rgb-to-hex --prefix "#" | str lowercase }
    [
        [sidebar_bg reset] [panel_bg reset] [active_row_bg $s.active_row_bg] [selection_bg $s.selection_bg]
        [accent $p.c4] [red $p.c1] [green $p.c2] [surface_dim $s.surface_dim] [surface0 $s.surface0]
        [surface1 $s.surface1] [overlay0 $s.overlay0] [overlay1 $s.overlay1] [text $p.fg] [subtext0 $s.subtext0]
        [yellow $p.c3] [blue $p.c4] [mauve $p.c5] [teal $p.c6] [peach $p.c11]
    ]
}

def config-text [cfg: record]: nothing -> string {
    let source = open --raw config/config.toml | text-render {PREFIX: $cfg.prefix, SIDEBAR_WIDTH: $cfg.sidebar_width}
    let p = palette-load
    if $p == null { return $source }
    let block = theme-custom $p | each {|kv| $'($kv.0) = "($kv.1)"' } | prepend "[theme.custom]" | str join "\n"
    $source | str replace --regex $BLOCK $"${1}($block)\n${2}"
}

def config [cfg: record]: nothing -> record {
    file-text (xdg config herdr config.toml) (config-text $cfg) --mode 600 --generated --then [$RELOAD]
}

export def link [cfg: record] {
    [
        (config $cfg)
        (link-commands scripts/herdr-open.nu scripts/herdr-fingers.nu)
        (file-copy config/herdr.tmpfiles.conf (xdg config user-tmpfiles.d herdr.conf))
    ]
}

export def theme [cfg: record, wallpaper: string] {
    config $cfg
}
