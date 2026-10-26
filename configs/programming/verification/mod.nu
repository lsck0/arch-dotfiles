use module.nu *

export const meta = {packages: {pacman: [apalache-bin cbmc tla-toolbox z3]}}

export def link [cfg: record] {
    desktop-override tla-toolbox.desktop {
        desktop-set {Version: "1.5", Categories: "Development;IDE;"}
    }
}
