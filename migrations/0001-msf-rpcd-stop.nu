# msf-rpcd.socket now listens on msfrpcd's old port: a daemon still running from the unit before it holds the port, and
# the socket could not bind on the apply that brings it
const UNIT = "msf-rpcd.service"

export def up []: nothing -> nothing {
    if (^systemctl --user is-active --quiet $UNIT | complete).exit_code == 0 { ^systemctl --user stop $UNIT }
}
