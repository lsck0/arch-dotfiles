use module.nu *

export const meta = {packages: {pacman: [teamspeak6-client]}}

const FLAGS = "--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations"

# a CEF app lands on xwayland at 1x from the stock entry; the ozone hint makes it native wayland. the stock Audio
# category needs AudioVideo beside it (desktop-file-validate), and a voice chat is Network's Chat and Telephony
export def link [cfg: record] {
    desktop-override teamspeak6-client.desktop {
        $in
        | str replace --all --regex '(?m)^(Exec=teamspeak6) ' $'$1 ($FLAGS) '
        | str replace --regex '(?m)^Categories=.*$' 'Categories=Network;Chat;Telephony;'
    }
}
