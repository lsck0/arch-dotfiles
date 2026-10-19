use module.nu *

export const meta = {packages: {pacman: [lib32-mangohud mangohud socat]}}

export def link [cfg: record] {
    [
        (files-into ($nu.home-dir | path join .config MangoHud) MangoHud.conf)
        (link-commands mangohud-toggle.nu)
    ]
}
