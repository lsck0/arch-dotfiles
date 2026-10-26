use module.nu *
use ../../core/wallust/font.nu [font-load]

export const meta = {deps: [desktop/oomox], packages: {pacman: [flat-remix-gtk gtk3 gtk4 nwg-look obsidian-icon-theme xdg-user-dirs-gtk]}}

const GTK_THEME = "oomox-colors-oomox"
const INTERFACE = "org.gnome.desktop.interface"

export def link [cfg: record] {
    let config = xdg config
    [
        # libadwaita ignores gtk-theme-name, so its gtk.css is oomox's export; dangling until the first theme switch
        (file-link ($nu.home-dir | path join .themes $GTK_THEME gtk-4.0 gtk.css) ($config | path join gtk-4.0 gtk.css))
    ]
}

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    let css = file-render gtk.css (xdg config gtk-3.0 gtk.css) {FONT: $font.family}
        | file-text $in.target $in.content --generated
    let p = palette-load
    if $p == null { return [$css] }
    let font = $"($font.family) ($font.ui_size)"
    let scheme = if $p.light == "1" { "prefer-light" } else { "prefer-dark" }
    let ini = ["[Settings]" $"gtk-theme-name=($GTK_THEME)" $"gtk-font-name=($font)"]
    let set = {|name, key, value| exec $name [gsettings set $INTERFACE $key $value] }
    [$css] | append ([gtk-3.0 gtk-4.0] | each {|dir|
        file-text (xdg config $dir settings.ini) ($ini | str join "\n" | $"($in)\n") --generated
    }) | append [
        (do $set gtk-scheme color-scheme $scheme)
        (do $set gtk-font font-name $font)
        # oomox's export flips it again once the theme files are new, which a running gtk3 app needs to reread them
        (do $set gtk-theme gtk-theme $GTK_THEME)
    ]
}
