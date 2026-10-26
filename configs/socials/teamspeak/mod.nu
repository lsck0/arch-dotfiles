use module.nu *

export const meta = {packages: {pacman: [teamspeak6-client]}}

const FLAGS = "--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations"

export def link [cfg: record] {
    desktop-override teamspeak6-client.desktop {
        $in
        | str replace --all --regex '(?m)^(Exec=teamspeak6) ' $'$1 ($FLAGS) '
        | desktop-set {Categories: "Network;Chat;Telephony;"}
    }
}
