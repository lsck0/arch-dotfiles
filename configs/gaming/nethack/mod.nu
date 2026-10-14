use module.nu *

export const meta = {packages: {pacman: [nethack]}}

const TMPFILES = "/etc/tmpfiles.d/nethack-sysconf.conf"

# arch's nethack 5.0.0-1 puts sysconf in /etc/nethack while the binary reads /var/games/nethack/sysconf, and its
# /usr/bin wrapper's HACKDIR drops the games gid so record is unwritable; drop both once `pacman -Ql nethack` lists
# /var/games/nethack/sysconf
export def system [cfg: record] {
    [
        (file-copy nethack-tmpfiles.conf $TMPFILES --then [systemd-tmpfiles --create $TMPFILES])
        # /usr/local/bin is ahead of /usr/bin on PATH, so terminals and nethack.desktop get this one
        (file-copy nethack.nu /usr/local/bin/nethack --mode 755)
    ]
}
