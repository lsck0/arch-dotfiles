use module.nu *
use ../spotify/mod.nu [spicetify-colors]
use ../../core/wallust/scripts/palette.nu [RADIUS_PX]
use ../../core/wallust/scripts/font.nu [font-load]

# its theme reads spotify's spicetify colours, as discord's does, so it runs after spotify's
export const meta = {deps: [socials/spotify], packages: {pacman: [fluxer-bin]}}

# a stable path in Fluxer's own config dir for the one link in README.md; Fluxer watches a linked file
const THEME = "wal.theme.css"

export def link [cfg: record] {
    # electron picks its secret store from XDG_CURRENT_DESKTOP, which hyprland is not, so the store is named
    desktop-exec app.fluxer.FluxerDesktop.desktop /usr/bin/fluxer --args [--password-store=gnome-libsecret]
}

export def theme [cfg: record, wallpaper: string] {
    let colors = spicetify-colors
    if $colors == null { return [] }
    let c = $colors | reduce --fold {} {|it, acc| $acc | insert $it.key $it.hex }
    file-render config/wal.theme.css (xdg config fluxer $THEME) {
        bg: $c.main, fg: $c.text, subtext: $c.subtext, accent: $c.button, elevated: $c.main-elevated
        highlight: $c.highlight, danger: $c.notification-error, radius: $RADIUS_PX, font: (font-load).family
    } --generated
}
