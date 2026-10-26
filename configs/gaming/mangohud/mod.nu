use module.nu *

export const meta = {packages: {pacman: [lib32-mangohud mangohud socat]}}

export const options = {
    font_size: {
        type: int
        default: 18
        doc: "MangoHud overlay text size in pixels, MangoHud.conf font_size"
        label: "Overlay font size"
        min: 8
        max: 64
        scope: user
    }
}

export def link [cfg: record] {
    [
        (file-render MangoHud.conf (xdg config MangoHud MangoHud.conf) {FONT_SIZE: $cfg.font_size})
        (link-commands mangohud-toggle.nu)
    ]
}
