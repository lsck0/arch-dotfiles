use module.nu *

export const meta = {packages: {pacman: [nethack]}}

export def system [cfg: record] {
    [
        # straight to the binary, bypassing arch's wrapper: keeps its games gid and compiled-in /var/games/nethack
        (file-link /usr/lib/nethack/nethack /usr/local/bin/nethack)
    ]
}
