# base/networkmanager's old 75-connectivity-check dispatcher switched NM's probe off at home through D-Bus, which NM
# keeps in its intern file over NetworkManager.conf; the probe now resolves at home (80-homelab-routes), so it goes
# back on. No NM on D-Bus (WSL): nothing was switched off.

export const layer = "system"

const NM = "org.freedesktop.NetworkManager"
const NM_PATH = "/org/freedesktop/NetworkManager"

export def up []: nothing -> nothing {
    if (do { ^busctl get-property $NM $NM_PATH $NM ConnectivityCheckAvailable } | complete).exit_code != 0 { return }
    ^busctl set-property $NM $NM_PATH $NM ConnectivityCheckEnabled b true
    do { ^busctl call --expect-reply=false $NM $NM_PATH $NM CheckConnectivity } | complete | ignore
}
