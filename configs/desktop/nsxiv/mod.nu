use module.nu *
use ../../core/wallust/palette.nu [hex-to-rgb readable-on rgb-to-hex shade]
use ../../core/wallust/font.nu [font-load]

export const meta = {deps: [core/trash core/wallust], packages: {pacman: [nsxiv xorg-xrdb]}}

const RESOURCES = "wal/colors-nsxiv.Xresources"
const BAR_SHADE = 0.075
const MARK_RATIO = 3.0

export def link [cfg: record] {
    file-copy exec/key-handler (xdg config nsxiv exec key-handler) --mode 755
}

# nsxiv reads only the X server's resources: merged here while Xwayland runs, and at login by hyprland_autostart.lua.
export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    let font = font-load
    let bg = $p.bg_conditioned | hex-to-rgb
    let bar = $bg | shade $BAR_SHADE
    let fg = $p.fg | hex-to-rgb
    let resources = {
        "window.background": $bg
        "window.foreground": ($fg | readable-on $bg)
        "bar.background": $bar
        "bar.foreground": ($fg | readable-on $bar)
        "mark.foreground": ($p.c4 | hex-to-rgb | readable-on $bg --ratio $MARK_RATIO)
    } | items {|key, color| $"Nsxiv.($key): ($color | rgb-to-hex --prefix '#')" }
    let file = xdg cache $RESOURCES
    let text = $resources | append $"Nsxiv.bar.font: ($font.mono)-($font.ui_size)" | str join "\n"
    let then = if (process-running Xwayland) { [xrdb -nocpp -merge $file] } else { [] }
    file-text $file $"($text)\n" --generated --then $then
}
