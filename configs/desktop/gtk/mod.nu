use module.nu *
use ../../core/wallust/font.nu [font-load]
use ../../core/wallust/palette.nu [ICON_THEMES]

export const meta = {deps: [desktop/oomox], packages: {pacman: [breeze-icons flat-remix-gtk gtk3 gtk4 nwg-look xdg-user-dirs-gtk]}}

const GTK_THEME = "oomox-colors-oomox"
const INTERFACE = "org.gnome.desktop.interface"
# every flatpak reads the host's theme: oomox lives in ~/.themes, settings.ini and the gtk4 gtk.css in the config dir
const FLATPAK_GLOBAL = "[Context]\nfilesystems=~/.themes:ro;xdg-config/gtk-3.0:ro;xdg-config/gtk-4.0:ro;\n"

export def link [cfg: record] {
    let config = xdg config
    let flatpak = if (which flatpak | is-empty) { [] } else {
        [(file-text (xdg data flatpak overrides global) $FLATPAK_GLOBAL)]
    }
    [
        # libadwaita ignores gtk-theme-name, so its gtk.css is oomox's export; dangling until the first theme switch
        (file-link ($nu.home-dir | path join .themes $GTK_THEME gtk-4.0 gtk.css) ($config | path join gtk-4.0 gtk.css))
    ] | append $flatpak
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    let css = file-render gtk.css (xdg config gtk-3.0 gtk.css) {FONT: $font.family}
        | file-text $in.target $in.content --generated
    let p = palette-load
    if $p == null { return [$css] }
    let mono = $"($font.mono) ($font.ui_size)"
    let font = $"($font.family) ($font.ui_size)"
    let light = $p.light == "1"
    let scheme = if $light { "prefer-light" } else { "prefer-dark" }
    let icons = if $light { $ICON_THEMES.light } else { $ICON_THEMES.dark }
    let ini = ["[Settings]" $"gtk-theme-name=($GTK_THEME)" $"gtk-font-name=($font)" $"gtk-icon-theme-name=($icons)"]
    let set = {|name, key, value| exec $name [gsettings set $INTERFACE $key $value] }
    [$css] | append ([gtk-3.0 gtk-4.0] | each {|dir|
        file-text (xdg config $dir settings.ini) ($ini | str join "\n" | $"($in)\n") --generated
    }) | append [
        (do $set gtk-scheme color-scheme $scheme)
        (do $set gtk-font font-name $font)
        (do $set gtk-mono-font monospace-font-name $mono)
        (do $set gtk-icons icon-theme $icons)
        # oomox's export flips it again once the theme files are new, which a running gtk3 app needs to reread them
        (do $set gtk-theme gtk-theme $GTK_THEME)
    ]
}
