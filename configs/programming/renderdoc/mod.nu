use module.nu *

export const meta = {packages: {pacman: [renderdoc]}}

# a config without its magic key is rejected with an error dialog and replaced by the defaults
const CONFIG_MAGIC = "rdocConfigData"
const CONFIG_VERSION = 1

# qrenderdoc cannot capture or replay a wayland window and picks wayland first from QT_QPA_PLATFORM=wayland;xcb
export def link [cfg: record] {
    [
        # its first start asks to send usage analytics
        (json-merge ($nu.home-dir | path join .local share qrenderdoc UI.config) [
            (json-set [$CONFIG_MAGIC] $CONFIG_VERSION)
            (json-set [Analytics_TotalOptOut] true)
        ])
    ] ++ (desktop-override renderdoc.desktop { str replace --all --regex "(?m)^Exec=qrenderdoc " "Exec=env QT_QPA_PLATFORM=xcb qrenderdoc " })
}
