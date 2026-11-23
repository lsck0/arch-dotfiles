use module.nu *

export const meta = {packages: {pacman: [element-desktop]}}

export def link [cfg: record] {
    # electron picks its secret store from XDG_CURRENT_DESKTOP, which hyprland is not, so the store is named
    desktop-exec io.element.Element.desktop /usr/bin/element-desktop --args [--password-store=gnome-libsecret]
}
