use module.nu *

export const meta = {packages: {pacman: [teamspeak6-client]}}

const FLAGS = "--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations"

# a CEF app: from the stock entry it lands on xwayland at 1x; the ozone hint makes it a native wayland client hyprland
# scales like any other. ts6's built-in default palette is already dark
export def link [cfg: record] {
    desktop-override teamspeak6-client.desktop {
        $in | str replace --all --regex '(?m)^(Exec=teamspeak6) ' $'$1 ($FLAGS) '
    }
}
