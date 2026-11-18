use module.nu *
use ../../core/wallust/font.nu [font-load]
use ../../core/wallust/palette.nu [ICON_THEMES RADIUS_PX hex-to-rgb rgb-to-hsv]
use ../cursor/mod.nu [CURSOR_SIZE_PX cursor-name]
use ../oomox/mod.nu [INTERFACE]

export const meta = {
    deps: [desktop/cursor desktop/oomox]
    reads: [desktop/hyprland]
    packages: {pacman: [breeze-icons flat-remix-gtk gtk-engine-murrine gtk3 gtk4 nwg-look xdg-user-dirs-gtk]}
}

const GTK_THEME = "oomox-colors-oomox"
# every flatpak reads the host's theme: oomox lives in ~/.themes, settings.ini and the gtk4 gtk.css in the config dir
const FLATPAK_GLOBAL = "[Context]\nfilesystems=~/.themes:ro;xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro;\n"
# no buttons on either side of a client-side title bar: Hyprland closes and moves windows
const BUTTON_LAYOUT = ":"
const WM_PREFERENCES = "org.gnome.desktop.wm.preferences"
# libadwaita offers only named accents: their hues in turns, slate for a grey accent below this saturation
const GNOME_ACCENTS = {blue: 0.592, teal: 0.525, green: 0.364, yellow: 0.114, orange: 0.064, red: 0.981, pink: 0.919, purple: 0.792}
const GNOME_SLATE_SATURATION = 0.25

# The named libadwaita accent nearest the palette's accent (c4, kdeglobals' AccentColor too).
def gnome-accent [hex: string]: nothing -> string {
    let hsv = $hex | hex-to-rgb | rgb-to-hsv
    if $hsv.1 < $GNOME_SLATE_SATURATION { return "slate" }
    $GNOME_ACCENTS | transpose name hue
    | each {|a| let d = ($a.hue - $hsv.0 | math abs); {name: $a.name, distance: ([$d (1 - $d)] | math min)} }
    | sort-by distance | first | get name
}

export def link [cfg: record] {
    if (which flatpak | is-not-empty) { file-text (xdg data flatpak overrides global) $FLATPAK_GLOBAL }
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    let css = file-render gtk.css (xdg config gtk-3.0 gtk.css) {FONT: $font.family} --generated
    # libadwaita ignores gtk-theme-name, so its gtk.css imports oomox's export; gtk expands no ~ in url()
    let theme_css = $nu.home-dir | path join .themes $GTK_THEME gtk-4.0 gtk.css
    let css4 = file-render gtk4.css (xdg config gtk-4.0 gtk.css) {THEME_CSS: $theme_css, RADIUS_PX: $RADIUS_PX} --generated
    let p = palette-load
    if $p == null { return [$css $css4] }
    let mono = $"($font.mono) ($font.ui_size)"
    let ui = $"($font.family) ($font.ui_size)"
    let light = $p.light == "1"
    let scheme = if $light { "prefer-light" } else { "prefer-dark" }
    let icons = if $light { $ICON_THEMES.light } else { $ICON_THEMES.dark }
    let cursor = cursor-name ($cfg.deps?."desktop/cursor"?.active? | default false)
    let ini = [
        "[Settings]" $"gtk-theme-name=($GTK_THEME)" $"gtk-font-name=($ui)" $"gtk-icon-theme-name=($icons)"
        $"gtk-decoration-layout=($BUTTON_LAYOUT)" $"gtk-cursor-theme-name=($cursor)"
        $"gtk-cursor-theme-size=($CURSOR_SIZE_PX)"
    ]
    # gtk2 under xwayland ignores GDK_SCALE and sees 96 dpi, so only its font can follow the xwayland scale
    let ui2 = $"($font.family) ($font.ui_size * (xwayland-scale-for $cfg))"
    let rc2 = [$"gtk-theme-name=\"($GTK_THEME)\"" $"gtk-icon-theme-name=\"($icons)\"" $"gtk-font-name=\"($ui2)\""
        $"gtk-cursor-theme-name=\"($cursor)\""
    ]
    let set = {|name, key, value| exec $name [gsettings set $INTERFACE $key $value] }
    [
        $css
        $css4
        ([gtk-3.0 gtk-4.0] | each {|dir| file-text (xdg config $dir settings.ini) ($ini | to text) --generated })
        (file-text (xdg config gtk-2.0 gtkrc) ($rc2 | to text) --generated)
        (do $set gtk-scheme color-scheme $scheme)
        (do $set gtk-font font-name $ui)
        (do $set gtk-document-font document-font-name $ui)
        (do $set gtk-mono-font monospace-font-name $mono)
        (do $set gtk-accent accent-color (gnome-accent $p.c4))
        (do $set gtk-icons icon-theme $icons)
        (do $set gtk-cursor cursor-theme $cursor)
        (do $set gtk-cursor-size cursor-size ($CURSOR_SIZE_PX | into string))
        (exec gtk-buttons [gsettings set $WM_PREFERENCES button-layout $BUTTON_LAYOUT])
        # oomox's export flips it again once the theme files are new, which a running gtk3 app needs to reread them
        (do $set gtk-theme gtk-theme $GTK_THEME)
    ]
}
