use module.nu *

export const meta = {reads: [desktop/hyprland], packages: {pacman: [renderdoc]}}

# a config without its magic key is rejected with an error dialog and replaced by the defaults
const CONFIG_MAGIC = "rdocConfigData"
const CONFIG_VERSION = 1

export def link [cfg: record] {
    let scale = xwayland-scale-for $cfg
    [
        (json-merge (xdg data qrenderdoc UI.config) [
            (json-set [$CONFIG_MAGIC] $CONFIG_VERSION)
            (json-set [Analytics_TotalOptOut] true)
        ])
        # qrenderdoc cannot capture or replay a wayland window and would pick wayland first; qt on xcb ignores
        # GDK_SCALE and sees 96 dpi, so it takes xwayland's scale itself
        (desktop-exec renderdoc.desktop qrenderdoc --env-vars {QT_QPA_PLATFORM: xcb, QT_SCALE_FACTOR: $scale})
    ]
}
