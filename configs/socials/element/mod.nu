use module.nu *

export const meta = {packages: {pacman: [element-desktop]}}

# arch's electron is already a native wayland client; it picks its secret store from XDG_CURRENT_DESKTOP, which
# hyprland is not, so element opens on a "System unsupported" keyring dialog without the store named
export def link [cfg: record] {
    desktop-override io.element.Element.desktop {
        $in | str replace --all --regex '(?m)^(Exec=/usr/bin/element-desktop) ' '$1 --password-store=gnome-libsecret '
    }
}
