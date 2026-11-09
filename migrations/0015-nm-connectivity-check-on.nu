# The removed 75-connectivity-check left NM's probe off in its intern file; it resolves at home now.

export const layer = "system"

const NM = "org.freedesktop.NetworkManager"
const NM_PATH = "/org/freedesktop/NetworkManager"

export def up []: nothing -> nothing {
    if (do { ^busctl get-property $NM $NM_PATH $NM ConnectivityCheckAvailable } | complete).exit_code != 0 { return }
    ^busctl set-property $NM $NM_PATH $NM ConnectivityCheckEnabled b true
    do { ^busctl call --expect-reply=false $NM $NM_PATH $NM CheckConnectivity } | complete | ignore
}
