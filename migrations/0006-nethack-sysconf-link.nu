# gaming/nethack's tmpfiles link /var/games/nethack/sysconf -> /etc/nethack/sysconf covered Arch's 5.0.0-1, whose
# binary read sysconf there; 5.0.0-2 reads /etc/nethack/sysconf itself. Left unowned, the link would fail any later
# package that ships that path ("exists in filesystem"), and pacman checks conflicts before a hook could remove it.
export const layer = "system"

const LINK = "/var/games/nethack/sysconf"

export def up []: nothing -> nothing {
    if ($LINK | path type) == symlink and (^pacman -Qo $LINK | complete).exit_code != 0 { rm $LINK }
}
