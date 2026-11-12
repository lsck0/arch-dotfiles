# syncthing's gui password and steam's launch options became recorded actions keyed in dot's state; their own stamps
# are read by nothing any more.

use module.nu [xdg]

export def up []: nothing -> nothing {
    rm --force (xdg state syncthing gui-password.stamp) (xdg state steam-launch-options.stamp)
}
