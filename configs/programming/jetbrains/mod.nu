use module.nu *

export const meta = {packages: {pacman: [jetbrains-toolbox]}}

export def link [cfg: record] {
    # toolbox rewrites its autostart entry on every start, so the generated unit is masked
    unit-mask "app-jetbrains\\x2dtoolbox@autostart.service"
}
