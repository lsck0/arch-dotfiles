use module.nu *

export const meta = {packages: {pacman: [flat-remix-gtk gtk3 gtk4 nwg-look obsidian-icon-theme xdg-user-dirs-gtk]}}

const GTK_THEME = "oomox-colors-oomox"
const INTERFACE = "org.gnome.desktop.interface"

export def link [cfg: record] {
    let config = $nu.home-dir | path join .config
    [
        # a link: toggle-font rewrites the repo file; an overlay on the oomox theme that palette regen never writes
        (file-link gtk.css ($config | path join gtk-3.0 gtk.css))
        # libadwaita ignores gtk-theme-name, so its gtk.css is the oodwaita export themix rewrites on every switch;
        # dangling before the first switch, libadwaita falls back until it exists
        (file-link ($nu.home-dir | path join .themes $GTK_THEME gtk-4.0 gtk.css) ($config | path join gtk-4.0 gtk.css))
    ]
}

def font-get []: nothing -> any {
    let toggle = $env.DOTFILES | path join scripts toggles toggle-font.nu
    let family = ^$toggle get | complete | get stdout | str trim
    let size = ^$toggle ui-size | complete | get stdout | str trim
    if ($family | is-empty) or $size !~ '^[0-9]+$' { null } else { $"($family) ($size)" }
}

# gtk follows the oomox export and the palette's light or dark scheme, through gsettings and settings.ini
export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    let font = font-get
    let scheme = if $p.light == "1" { "prefer-light" } else { "prefer-dark" }
    let ini = ["[Settings]" $"gtk-theme-name=($GTK_THEME)"] | append (if $font == null { [] } else { [$"gtk-font-name=($font)"] })
    let set = {|name, key, value| exec $name [gsettings set $INTERFACE $key $value] }
    [gtk-3.0 gtk-4.0] | each {|dir|
        file-text ($nu.home-dir | path join .config $dir settings.ini) ($ini | str join "\n" | $"($in)\n") --generated
    } | append [
        (do $set gtk-scheme color-scheme $scheme)
        (if $font == null { [] } else { do $set gtk-font font-name $font })
        # running gtk3 apps reload only on a theme name change, so flip it away and back
        (do $set gtk-theme-clear gtk-theme "")
        (do $set gtk-theme gtk-theme $GTK_THEME)
    ]
}
