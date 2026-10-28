use module.nu *

export const meta = {packages: {pacman: [nethack]}}

const TMPFILES = "/etc/tmpfiles.d/nethack-sysconf.conf"

# Arch's nethack 5.0.0-1 misplaces sysconf; drop once `pacman -Ql nethack` lists /var/games/nethack/sysconf
export def system [cfg: record] {
    [
        (file-copy nethack-tmpfiles.conf $TMPFILES --then [systemd-tmpfiles --create $TMPFILES])
        # straight to the binary, bypassing arch's wrapper: keeps its games gid and compiled-in /var/games/nethack
        (file-link /usr/lib/nethack/nethack /usr/local/bin/nethack)
    ]
}
