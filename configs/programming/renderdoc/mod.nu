use module.nu *

export const meta = {packages: {pacman: [renderdoc]}}

# a config without its magic key is rejected with an error dialog and replaced by the defaults
const CONFIG_MAGIC = "rdocConfigData"
const CONFIG_VERSION = 1

export def link [cfg: record] {
    [
        (json-merge (xdg data qrenderdoc UI.config) [
            (json-set [$CONFIG_MAGIC] $CONFIG_VERSION)
            (json-set [Analytics_TotalOptOut] true)
        ])
    # qrenderdoc cannot capture or replay a wayland window and would pick wayland first
    ] ++ (desktop-override renderdoc.desktop { str replace --all --regex "(?m)^Exec=qrenderdoc " "Exec=env QT_QPA_PLATFORM=xcb qrenderdoc " })
}
