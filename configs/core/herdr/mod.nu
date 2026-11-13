use module.nu *
use ../wallust/palette.nu [hex-to-rgb rgb-to-hex tone-map mix]

export const meta = {deps: [core/cli core/wallust], packages: {pacman: [herdr-bin]}}

const BLOCK = '(?s)(# BEGIN PYWAL THEME\n).*?(# END PYWAL THEME)'
const DARK_FLOOR = 0.16
const BLENDS = {
    active_row_bg: 0.06, selection_bg: 0.11, surface_dim: 0.0, surface0: 0.08, surface1: 0.14, overlay0: 0.22
    overlay1: 0.34, subtext0: 0.65
}
# a server that is not running reads the new file when it starts
const RELOAD = [sh -c "herdr server reload-config >/dev/null 2>&1 || true"]

def config-text []: nothing -> string {
    let source = open --raw config.toml
    let p = palette-load
    if $p == null { return $source }
    let bg = if $p.light == "1" { $p.bg_conditioned } else {
        $p.bg_conditioned | hex-to-rgb | tone-map --lo $DARK_FLOOR --hi 1.0 | rgb-to-hex --prefix "#"
    }
    let bg_rgb = $bg | hex-to-rgb
    let fg_rgb = $p.fg | hex-to-rgb
    let s = $BLENDS | update cells { mix $bg_rgb $fg_rgb $in | rgb-to-hex --prefix "#" | str lowercase }
    let theme = [
        [sidebar_bg reset] [panel_bg reset] [active_row_bg $s.active_row_bg] [selection_bg $s.selection_bg]
        [accent $p.c4] [red $p.c1] [green $p.c2] [surface_dim $s.surface_dim] [surface0 $s.surface0]
        [surface1 $s.surface1] [overlay0 $s.overlay0] [overlay1 $s.overlay1] [text $p.fg] [subtext0 $s.subtext0]
        [yellow $p.c3] [blue $p.c4] [mauve $p.c5] [teal $p.c6] [peach $p.c11]
    ]
    let block = $theme | each {|kv| $'($kv.0) = "($kv.1)"' } | prepend "[theme.custom]" | str join "\n"
    $source | str replace --regex $BLOCK $"${1}($block)\n${2}"
}

def config []: nothing -> record {
    file-text (xdg config herdr config.toml) (config-text) --mode 600 --generated --then $RELOAD
}

export def link [cfg: record] {
    [
        (config)
        (link-commands herdr-open.nu herdr-fingers.nu)
        (file-copy herdr.tmpfiles.conf (xdg config user-tmpfiles.d herdr.conf))
    ]
}

export def theme [cfg: record, wallpaper: string] {
    config
}
