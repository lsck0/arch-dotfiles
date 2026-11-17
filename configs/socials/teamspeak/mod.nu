use module.nu *

export const meta = {packages: {pacman: [teamspeak6-client]}}

export def link [cfg: record] {
    # X11 on purpose: its push-to-talk helper reads keys through XInput only, so a native Wayland window never sees
    # the key; Hyprland passes F13 to it (desktop/hyprland keybindings)
    desktop-override teamspeak6-client.desktop { desktop-set {Categories: "Network;Chat;Telephony;"} }
}
