use module.nu *

export const meta = {packages: {pacman: [nethack]}}

const TMPFILES = "/etc/tmpfiles.d/nethack-sysconf.conf"

# Arch's nethack 5.0.0-1 misplaces sysconf; drop once `pacman -Ql nethack` lists /var/games/nethack/sysconf
export def system [cfg: record] {
    [
        (file-copy nethack-tmpfiles.conf $TMPFILES --then [systemd-tmpfiles --create $TMPFILES])
        (file-copy nethack.nu /usr/local/bin/nethack --mode 755)
    ]
}
