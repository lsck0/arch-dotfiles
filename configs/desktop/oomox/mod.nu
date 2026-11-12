use module.nu *
use ../../core/wallust/palette.nu [palette-rgb condition-bg vivify shade selection-pair readable-on is-light rgb-to-hex RADIUS_PX SHADE_CHROME]

export const meta = {packages: {pacman: [themix-gui-git themix-plugin-base16-git xorg-server-xvfb]}}

const EXPORT_DIR = ".config/oomox/export_config"
const EXPORT_CONFIG = "multi_export_oodwaita.json"
const COLORS = "wal/colors-oomox"
# themix-multi-export can hang forever on an oomox gtk-loop bug sigterm cannot reap
const THEMIX_TIMEOUT = [timeout -k 5 20]
export const INTERFACE = "org.gnome.desktop.interface"

export def link [cfg: record] {
    [
        (files-into ($nu.home-dir | path join $EXPORT_DIR) $EXPORT_CONFIG)
        (desktop-override com.github.themix_project.Oomox.desktop { desktop-set {NoDisplay: true} })
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-rgb "oomox theme"
    if $p == null { return [] }
    let bg = $p.bg | condition-bg
    let fg = $p.fg
    let accent = $p.c4 | vivify 0.45 0.55
    let selection = $accent | selection-pair $fg
    let hex = {|c| $c | rgb-to-hex }
    let on = {|c| $fg | readable-on $c | rgb-to-hex }
    let menu = $bg | shade $SHADE_CHROME
    let txt = $bg | shade 0.02
    let btn = $bg | shade 0.075
    let hdr_btn = $bg | shade 0.03
    let values = {
        NAME: wal, BG: (do $hex $bg), FG: (do $on $bg), MENU_BG: (do $hex $menu), MENU_FG: (do $on $menu)
        SEL_BG: (do $hex $selection.0), SEL_FG: (do $hex $selection.1), TXT_BG: (do $hex $txt), TXT_FG: (do $on $txt)
        BTN_BG: (do $hex $btn), BTN_FG: (do $on $btn), HDR_BTN_BG: (do $hex $hdr_btn), HDR_BTN_FG: (do $on $hdr_btn)
        GTK3_GENERATE_DARK: (if ($bg | is-light) { "False" } else { "True" }), ROUNDNESS: $RADIUS_PX, SPACING: 3, GRADIENT: "0.0"
    }
    let text = $values | items {|k, v| $"($k)=($v)" } | str join "\n"
    [(file-text (xdg cache $COLORS) $"($text)\n" --generated --then (then-step themix-export))]
}

# Exports the gtk themes from the wallust colors, always under Xvfb: themix cannot init gtk headless, and on the
# session's display it maps a window for a moment (a flash in a corner on every theme switch)
export def themix-export []: nothing -> nothing {
    # xvfb-run sleeps a fixed 3s for Xvfb to come up; it is listening in well under one
    let argv = $THEMIX_TIMEOUT ++ [xvfb-run -a -w 1 -e /dev/stderr themix-multi-export]
    let out = with-env {GDK_BACKEND: x11, WAYLAND_DISPLAY: null} {
        ^($argv | first) ...($argv | skip 1) ($nu.home-dir | path join $EXPORT_DIR $EXPORT_CONFIG) (xdg cache $COLORS) o+e>| complete
    }
    if $out.exit_code != 0 {
        error make {msg: $"themix export ($EXPORT_CONFIG) exited ($out.exit_code): ($out.stdout | lines | last 6 | str join ' ')"}
    }
    # running gtk3 apps reread the exported theme only on a theme name change, so it is flipped away and back
    let theme = ^gsettings get $INTERFACE gtk-theme | complete | get stdout | str trim | str trim --char "'"
    if ($theme | is-empty) { return }
    ^gsettings set $INTERFACE gtk-theme "" | complete | ignore
    ^gsettings set $INTERFACE gtk-theme $theme | complete | ignore
}
