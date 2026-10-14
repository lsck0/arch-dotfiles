use module.nu *

export const meta = {packages: {pacman: [jetbrains-toolbox]}}

# toolbox rewrites its autostart entry on every start, so the unit the xdg autostart generator makes from it is masked
export def link [cfg: record] {
    unit-mask "app-jetbrains\\x2dtoolbox@autostart.service"
}
