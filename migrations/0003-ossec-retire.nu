# base/wazuh replaced base/ossec: its packages, its alert data and the group the bar read alerts through go
export const layer = "system"

const PACKAGES = [ossec-hids-local czmq-git]
const DATA = "/var/lib/ossec-hids"
const GROUP = "ossec-alerts"

export def up []: nothing -> nothing {
    ^systemctl disable --now ossec-server.target ossec-journal.service | complete
    let installed = $PACKAGES | where { (^pacman -Q $in | complete).exit_code == 0 }
    # --unneeded skips one another package still requires, which would otherwise fail the run and block every later one
    if ($installed | is-not-empty) { ^pacman -Rnsu --noconfirm ...$installed }
    rm --recursive --force $DATA
    if (^getent group $GROUP | complete).exit_code == 0 { ^groupdel $GROUP }
}
