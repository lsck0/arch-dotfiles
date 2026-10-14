use module.nu *

export const meta = {packages: {pacman: [element-desktop]}}

# electron picks its secret store from XDG_CURRENT_DESKTOP, which hyprland is not, so the store is named
export def link [cfg: record] {
    desktop-override io.element.Element.desktop {
        $in | str replace --all --regex '(?m)^(Exec=/usr/bin/element-desktop) ' '$1 --password-store=gnome-libsecret '
    }
}
