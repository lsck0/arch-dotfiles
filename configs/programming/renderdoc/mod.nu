use module.nu *

export const meta = {packages: {pacman: [renderdoc]}}

# qrenderdoc cannot capture or replay a wayland window and picks wayland first from QT_QPA_PLATFORM=wayland;xcb
export def link [cfg: record] {
    desktop-override renderdoc.desktop { str replace --all --regex "(?m)^Exec=qrenderdoc " "Exec=env QT_QPA_PLATFORM=xcb qrenderdoc " }
}
