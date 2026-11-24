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
    position: {
        type: string
        default: top-left
        doc: "MangoHud overlay corner, MangoHud.conf position"
        label: "Overlay position"
        choices: [top-left top-center top-right middle-left middle-right bottom-left bottom-center bottom-right]
        scope: user
    }
}

export def link [cfg: record] {
    [
        (file-render config/MangoHud.conf (xdg config MangoHud MangoHud.conf) {FONT_SIZE: $cfg.font_size, POSITION: $cfg.position})
        (link-commands scripts/mangohud-toggle.nu)
    ]
}
