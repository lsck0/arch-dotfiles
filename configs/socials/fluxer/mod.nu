use module.nu *

export const meta = {packages: {pacman: [fluxer-bin]}}

export def link [cfg: record] {
    # electron picks its secret store from XDG_CURRENT_DESKTOP, which hyprland is not, so the store is named
    desktop-exec app.fluxer.FluxerDesktop.desktop /usr/bin/fluxer --args [--password-store=gnome-libsecret]
}
